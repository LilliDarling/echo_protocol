import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {validateRequest} from "../utils/validation.js";
import {createHash, randomBytes} from "crypto";
import * as ed from "@noble/ed25519";
import {sha512} from "@noble/hashes/sha2.js";
import {db} from "../firebase.js";

// Enable both sync and async methods for @noble/ed25519 v3
ed.hashes.sha512 = sha512;
ed.hashes.sha512Async = (msg: Uint8Array) => Promise.resolve(sha512(msg));

/**
 * Generate a short correlation ID for logging.
 * Does NOT reveal the actual invite code or user ID.
 * @return {string} 8-character hex correlation ID
 */
function generateCorrelationId(): string {
  return randomBytes(4).toString("hex");
}

export const acceptPartnerInvite = onCall(
  {
    maxInstances: 10,
    cors: true,
  },
  async (request) => {
    validateRequest(request);

    const correlationId = generateCorrelationId();

    const userId = request.auth?.uid as string;
    const {inviteCode, myPublicKey, myKeyVersion} = request.data;

    if (!inviteCode || typeof inviteCode !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Invite code is required"
      );
    }

    const normalizedCode = inviteCode.toUpperCase().replace(/[-\s]/g, "");
    const isValidFormat =
      normalizedCode.length === 12 && /^[A-Z0-9]+$/.test(normalizedCode);
    if (!isValidFormat) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid invite code format"
      );
    }

    if (!myPublicKey || typeof myPublicKey !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Public key is required"
      );
    }

    let keyVersion: number;
    if (typeof myKeyVersion === "number") {
      keyVersion = myKeyVersion;
    } else if (typeof myKeyVersion === "string") {
      keyVersion = parseInt(myKeyVersion, 10);
      if (isNaN(keyVersion)) {
        throw new HttpsError(
          "invalid-argument",
          "Key version must be a valid number"
        );
      }
    } else {
      throw new HttpsError(
        "invalid-argument",
        "Key version is required"
      );
    }

    logger.info("Partner invite acceptance attempt", {
      correlationId,
    });

    try {
      const inviteRef = db.collection("partnerInvites").doc(normalizedCode);
      const inviteDoc = await inviteRef.get();

      if (!inviteDoc.exists) {
        throw new HttpsError("not-found", "Invalid invite code");
      }

      const inviteData = inviteDoc.data();
      if (!inviteData) {
        throw new HttpsError("not-found", "Invalid invite code");
      }

      if (inviteData.signatureVersion !== 4) {
        logger.warn("Invalid signature version", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      if (!inviteData.ed25519PublicKey ||
          typeof inviteData.ed25519PublicKey !== "string") {
        logger.warn("Missing Ed25519 public key", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      if (!inviteData.signature ||
          typeof inviteData.signature !== "string") {
        logger.warn("Missing signature", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      if (!inviteData.publicKey ||
          typeof inviteData.publicKey !== "string" ||
          inviteData.publicKey.length < 50) {
        logger.warn("Invalid public key", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      if (!inviteData.userName || typeof inviteData.userName !== "string") {
        logger.warn("Missing userName", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      if (!inviteData.publicKeyFingerprint ||
          typeof inviteData.publicKeyFingerprint !== "string") {
        logger.warn("Missing fingerprint", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      if (typeof inviteData.publicKeyVersion !== "number" &&
          typeof inviteData.publicKeyVersion !== "string") {
        logger.warn("Missing keyVersion", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      try {
        const signatureBytes = Buffer.from(inviteData.signature, "base64");
        const publicKeyBytes = Buffer.from(
          inviteData.ed25519PublicKey,
          "base64"
        );

        if (publicKeyBytes.length !== 32) {
          logger.warn("Invalid Ed25519 public key length", {correlationId});
          throw new HttpsError("failed-precondition", "Invalid invite");
        }

        if (signatureBytes.length !== 64) {
          logger.warn("Invalid Ed25519 signature length", {correlationId});
          throw new HttpsError("failed-precondition", "Invalid invite");
        }

        const computedHash = createHash("sha256")
          .update(inviteData.publicKey)
          .digest("hex");

        if (inviteData.publicKeyHash !== computedHash) {
          logger.warn("Public key hash mismatch", {correlationId});
          throw new HttpsError("failed-precondition", "Invalid invite");
        }

        const expiresAtMs = inviteData.expiresAt.toDate().getTime();
        const fp = inviteData.publicKeyFingerprint;
        const ver = inviteData.publicKeyVersion;
        const payload = `${normalizedCode}:${inviteData.userId}:` +
          `${computedHash}:${inviteData.userName}:${fp}:${ver}:` +
          `${expiresAtMs}`;
        const payloadBytes = Buffer.from(payload, "utf-8");

        // Detailed debug logging
        logger.info("Verification inputs", {
          correlationId,
          payload,
          payloadHex: payloadBytes.toString("hex"),
          signatureHex: signatureBytes.toString("hex"),
          pubKeyHex: publicKeyBytes.toString("hex"),
          signatureLen: signatureBytes.length,
          pubKeyLen: publicKeyBytes.length,
        });

        try {
          // Convert standard Node Buffers to Uint8Arrays for Noble
          const sig = new Uint8Array(signatureBytes);
          const msg = new Uint8Array(payloadBytes);
          const pub = new Uint8Array(publicKeyBytes);

          // Use verifyAsync for @noble/ed25519 v3
          const isValid = await ed.verifyAsync(sig, msg, pub);

          logger.info("Verification result", {
            correlationId,
            isValid,
            isValidType: typeof isValid,
          });

          if (!isValid) {
            logger.warn(
              "Ed25519 signature verification failed",
              {correlationId}
            );
            throw new HttpsError(
              "failed-precondition",
              "Invalid invite signature"
            );
          }
        } catch (err) {
          if (err instanceof HttpsError) {
            throw err;
          }
          logger.error(
            "Noble Ed25519 verification error",
            {error: String(err), correlationId}
          );
          throw new HttpsError("internal", "Signature processing failed");
        }

        logger.info("Ed25519 signature verified", {correlationId});

        // CRITICAL: Verify Ed25519 key binding
        // The ed25519PublicKey MUST match the user's registered identity key
        const inviteCreatorDoc = await db.collection("users")
          .doc(inviteData.userId)
          .get();

        if (!inviteCreatorDoc.exists) {
          logger.warn("Invite creator not found", {correlationId});
          throw new HttpsError("failed-precondition", "Invalid invite");
        }

        const creatorData = inviteCreatorDoc.data();
        const registeredIdentityKey = creatorData?.identityKey;

        if (!registeredIdentityKey ||
            typeof registeredIdentityKey.ed25519 !== "string") {
          logger.warn("No registered identity key", {correlationId});
          throw new HttpsError("failed-precondition", "Invalid invite");
        }

        if (inviteData.ed25519PublicKey !== registeredIdentityKey.ed25519) {
          logger.warn("Ed25519 key binding failed", {correlationId});
          throw new HttpsError("failed-precondition", "Invalid invite");
        }

        logger.info("Ed25519 key binding verified", {correlationId});
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        logger.error("Signature verification error", {correlationId});
        throw new HttpsError("failed-precondition", "Invalid invite");
      }

      const expiresAt = inviteData.expiresAt.toDate();
      if (expiresAt < new Date()) {
        throw new HttpsError(
          "failed-precondition",
          "This invite has expired"
        );
      }

      const partnerId = inviteData.userId;

      if (partnerId === userId) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot accept your own invite"
        );
      }

      const partnerPublicKey = inviteData.publicKey;
      let partnerKeyVersion = 1;
      if (typeof inviteData.publicKeyVersion === "string") {
        partnerKeyVersion = parseInt(inviteData.publicKeyVersion, 10) || 1;
      } else if (typeof inviteData.publicKeyVersion === "number") {
        partnerKeyVersion = inviteData.publicKeyVersion;
      }
      const partnerName = inviteData.userName;

      // ATOMIC TRANSACTION: All state checks and updates happen atomically
      await db.runTransaction(async (transaction) => {
        const txInviteDoc = await transaction.get(inviteRef);
        const txCurrentUserDoc = await transaction.get(
          db.collection("users").doc(userId)
        );
        const txPartnerDoc = await transaction.get(
          db.collection("users").doc(partnerId)
        );

        const txInviteData = txInviteDoc.data();
        if (!txInviteDoc.exists || !txInviteData) {
          throw new HttpsError("not-found", "Invalid invite code");
        }

        if (txInviteData.used) {
          throw new HttpsError(
            "failed-precondition",
            "This invite has already been used"
          );
        }

        if (!txCurrentUserDoc.exists) {
          throw new HttpsError("not-found", "User not found");
        }
        const txCurrentUserData = txCurrentUserDoc.data();
        if (txCurrentUserData?.partnerId) {
          throw new HttpsError(
            "failed-precondition",
            "You already have a partner linked"
          );
        }

        if (!txPartnerDoc.exists) {
          throw new HttpsError("not-found", "Partner not found");
        }
        const txPartnerData = txPartnerDoc.data();
        if (txPartnerData?.partnerId) {
          throw new HttpsError(
            "failed-precondition",
            "This user is already linked"
          );
        }

        transaction.update(inviteRef, {
          used: true,
          usedAt: FieldValue.serverTimestamp(),
          usedBy: userId,
        });

        // Hash partner IDs for secure cross-user reads
        // partnerIdHash allows partner to read this user's document
        const userPartnerIdHash = createHash("sha256")
          .update(partnerId)
          .digest("hex");
        const partnerPartnerIdHash = createHash("sha256")
          .update(userId)
          .digest("hex");

        transaction.update(db.collection("users").doc(userId), {
          partnerId: partnerId,
          partnerIdHash: userPartnerIdHash,
          partnerPublicKey: partnerPublicKey,
          partnerKeyVersion: partnerKeyVersion,
          partnerLinkedAt: FieldValue.serverTimestamp(),
        });

        transaction.update(db.collection("users").doc(partnerId), {
          partnerId: userId,
          partnerIdHash: partnerPartnerIdHash,
          partnerPublicKey: myPublicKey,
          partnerKeyVersion: keyVersion,
          partnerLinkedAt: FieldValue.serverTimestamp(),
        });

        const sortedIds = [userId, partnerId].sort();
        const conversationId = `${sortedIds[0]}_${sortedIds[1]}`;

        transaction.set(db.collection("conversations").doc(conversationId), {
          participants: [userId, partnerId],
          createdAt: FieldValue.serverTimestamp(),
          lastMessageAt: FieldValue.serverTimestamp(),
          lastMessage: null,
          unreadCount: {
            [userId]: 0,
            [partnerId]: 0,
          },
        });
      });

      await db.collection("security_logs").add({
        userId,
        event: "partner_linked",
        timestamp: FieldValue.serverTimestamp(),
        details: {partnerId},
      });

      logger.info("Partner linking successful", {correlationId});

      return {
        success: true,
        partnerId: partnerId,
        partnerName: partnerName,
        partnerPublicKey: partnerPublicKey,
        partnerKeyVersion: partnerKeyVersion,
        partnerFingerprint: inviteData.publicKeyFingerprint,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("Partner invite acceptance error", {correlationId});
      throw new HttpsError("internal", "Failed to accept invite");
    }
  }
);
