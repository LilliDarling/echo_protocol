import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue} from "firebase-admin/firestore";
import {
  UploadPreKeysRequest,
  UploadPreKeysResponse,
} from "../types/prekey.js";
import {db} from "../firebase.js";

const MAX_BATCH_SIZE = 100;

export const uploadPreKeys = onCall<UploadPreKeysRequest>(
  {
    // TODO: Re-enable after configuring AppCheck on client
    // enforceAppCheck: true,
    maxInstances: 10,
    cors: true,
  },
  async (request): Promise<UploadPreKeysResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const userId = request.auth.uid;
    const {identityKey, signedPrekey, oneTimePrekeys} = request.data;

    const noKeys = !identityKey && !signedPrekey &&
      (!oneTimePrekeys || oneTimePrekeys.length === 0);
    if (noKeys) {
      throw new HttpsError(
        "invalid-argument",
        "At least one key type must be provided"
      );
    }

    if (oneTimePrekeys && oneTimePrekeys.length > MAX_BATCH_SIZE) {
      throw new HttpsError(
        "invalid-argument",
        `Maximum ${MAX_BATCH_SIZE} one-time prekeys per upload`
      );
    }

    const userRef = db.collection("users").doc(userId);

    let uploadedCount = 0;

    await db.runTransaction(async (transaction) => {
      // READS FIRST: Firestore requires all reads before any writes
      const metadataCol = userRef.collection("metadata");
      const countRef = metadataCol.doc("prekeyCount");
      let countDoc = null;
      if (oneTimePrekeys && oneTimePrekeys.length > 0) {
        countDoc = await transaction.get(countRef);
      }

      // VALIDATION AND PREPARE DATA
      const updateData: Record<string, unknown> = {};

      if (identityKey) {
        const hasEd = identityKey.ed25519;
        const hasX = identityKey.x25519;
        const hasId = identityKey.keyId;
        if (!hasEd || !hasX || !hasId) {
          throw new HttpsError(
            "invalid-argument",
            "Invalid identity key format"
          );
        }
        updateData.identityKey = identityKey;
      }

      if (signedPrekey) {
        const hasKey = signedPrekey.publicKey;
        const hasSig = signedPrekey.signature;
        const validId = typeof signedPrekey.id === "number";
        const validExp = typeof signedPrekey.expiresAt === "number";
        if (!hasKey || !hasSig || !validId || !validExp) {
          throw new HttpsError(
            "invalid-argument",
            "Invalid signed prekey format"
          );
        }
        updateData.signedPrekey = signedPrekey;
      }

      // WRITES: All writes happen after reads
      if (Object.keys(updateData).length > 0) {
        transaction.set(userRef, updateData, {merge: true});
      }

      if (oneTimePrekeys && oneTimePrekeys.length > 0) {
        const otpCollection = userRef.collection("oneTimePrekeys");

        for (const otp of oneTimePrekeys) {
          if (!otp.publicKey || typeof otp.id !== "number") {
            throw new HttpsError(
              "invalid-argument",
              "Invalid one-time prekey format"
            );
          }
          const otpRef = otpCollection.doc(otp.id.toString());
          const timestamp = FieldValue.serverTimestamp();
          transaction.set(otpRef, {
            id: otp.id,
            publicKey: otp.publicKey,
            createdAt: timestamp,
          });
          uploadedCount++;
        }

        const countData = countDoc?.data();
        const currentCount = countDoc?.exists ? countData?.count || 0 : 0;
        const newCount = currentCount + uploadedCount;
        transaction.set(countRef, {count: newCount}, {merge: true});
      }
    });

    return {success: true, uploadedCount};
  }
);
