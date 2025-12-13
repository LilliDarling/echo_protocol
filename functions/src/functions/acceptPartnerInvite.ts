import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {validateRequest} from "../utils/validation";

const db = admin.firestore();

export const acceptPartnerInvite = onCall(
  {
    maxInstances: 10,
    cors: true,
  },
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const {inviteCode, myPublicKey, myKeyVersion} = request.data;

    // Validate inputs
    if (!inviteCode || typeof inviteCode !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Invite code is required"
      );
    }

    const normalizedCode = inviteCode.toUpperCase().replace(/[-\s]/g, "");
    const isValidFormat = normalizedCode.length === 8 &&
      /^[A-Z0-9]+$/.test(normalizedCode);
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

    // Handle both string and number for myKeyVersion
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
      userId,
      inviteCode: normalizedCode,
    });

    try {
      // Get the invite document
      const inviteRef = db.collection("partnerInvites").doc(normalizedCode);
      const inviteDoc = await inviteRef.get();

      if (!inviteDoc.exists) {
        throw new HttpsError("not-found", "Invalid invite code");
      }

      const inviteData = inviteDoc.data();
      if (!inviteData) {
        throw new HttpsError("not-found", "Invalid invite code");
      }

      // Check if invite is already used
      if (inviteData.used) {
        throw new HttpsError(
          "failed-precondition",
          "This invite has already been used"
        );
      }

      // Check if invite has expired
      const expiresAt = inviteData.expiresAt.toDate();
      if (expiresAt < new Date()) {
        throw new HttpsError(
          "failed-precondition",
          "This invite has expired"
        );
      }

      const partnerId = inviteData.userId;

      // Cannot accept own invite
      if (partnerId === userId) {
        throw new HttpsError(
          "failed-precondition",
          "You cannot accept your own invite"
        );
      }

      // Check if current user already has a partner
      const currentUserDoc = await db.collection("users").doc(userId).get();
      if (!currentUserDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }
      const currentUserData = currentUserDoc.data();
      if (currentUserData?.partnerId) {
        throw new HttpsError(
          "failed-precondition",
          "You already have a partner linked"
        );
      }

      // Check if invite creator already has a partner
      const partnerDoc = await db.collection("users").doc(partnerId).get();
      if (!partnerDoc.exists) {
        throw new HttpsError("not-found", "Partner not found");
      }
      const partnerData = partnerDoc.data();
      if (partnerData?.partnerId) {
        throw new HttpsError(
          "failed-precondition",
          "This user is already linked"
        );
      }

      // All validations passed - perform the linking transaction
      const partnerPublicKey = inviteData.publicKey;
      // Handle both string and number types for keyVersion
      let partnerKeyVersion = 1;
      if (typeof inviteData.publicKeyVersion === "string") {
        partnerKeyVersion = parseInt(inviteData.publicKeyVersion, 10) || 1;
      } else if (typeof inviteData.publicKeyVersion === "number") {
        partnerKeyVersion = inviteData.publicKeyVersion;
      }
      const partnerName = inviteData.userName;

      await db.runTransaction(async (transaction) => {
        // Mark invite as used
        transaction.update(inviteDoc.ref, {
          used: true,
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
          usedBy: userId,
        });

        // Update current user with partner info
        transaction.update(db.collection("users").doc(userId), {
          partnerId: partnerId,
          partnerPublicKey: partnerPublicKey,
          partnerKeyVersion: partnerKeyVersion,
          partnerLinkedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update partner with current user's info
        transaction.update(db.collection("users").doc(partnerId), {
          partnerId: userId,
          partnerPublicKey: myPublicKey,
          partnerKeyVersion: keyVersion,
          partnerLinkedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Create conversation document
        const sortedIds = [userId, partnerId].sort();
        const conversationId = `${sortedIds[0]}_${sortedIds[1]}`;

        transaction.set(db.collection("conversations").doc(conversationId), {
          participants: [userId, partnerId],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
          lastMessage: null,
          unreadCount: {
            [userId]: 0,
            [partnerId]: 0,
          },
        });
      });

      // Log security event
      await db.collection("security_logs").add({
        userId,
        event: "partner_linked",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        details: {partnerId},
      });

      logger.info("Partner linking successful", {userId, partnerId});

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
      const errorMessage = error instanceof Error ?
        error.message : String(error);
      logger.error("Partner invite acceptance error", {
        userId,
        errorMessage,
      });
      throw new HttpsError("internal", "Failed to accept invite");
    }
  }
);
