import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  GetPreKeyBundleRequest,
  PreKeyBundleResponse,
} from "../types/prekey";

export const getPreKeyBundle = onCall<GetPreKeyBundleRequest>(
  {
    enforceAppCheck: true,
    maxInstances: 10,
    cors: true,
  },
  async (request): Promise<PreKeyBundleResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const {recipientId} = request.data;

    if (!recipientId) {
      throw new HttpsError("invalid-argument", "recipientId is required");
    }

    if (recipientId === request.auth.uid) {
      throw new HttpsError(
        "invalid-argument",
        "Cannot fetch own prekey bundle"
      );
    }

    const db = admin.firestore();
    const userRef = db.collection("users").doc(recipientId);

    return await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data() ?? {};

      if (!userData.identityKey || !userData.signedPrekey) {
        throw new HttpsError(
          "failed-precondition",
          "User has not set up encryption keys"
        );
      }

      const otpCollection = userRef.collection("oneTimePrekeys");
      const otpQuery = otpCollection.orderBy("id").limit(1);
      const otpSnapshot = await transaction.get(otpQuery);

      let oneTimePrekey: {id: number; publicKey: string} | undefined;

      if (!otpSnapshot.empty) {
        const otpDoc = otpSnapshot.docs[0];
        const otpData = otpDoc.data();
        oneTimePrekey = {
          id: otpData.id,
          publicKey: otpData.publicKey,
        };
        transaction.delete(otpDoc.ref);

        const metadataCol = userRef.collection("metadata");
        const countRef = metadataCol.doc("prekeyCount");
        const countDoc = await transaction.get(countRef);
        const countData = countDoc.data();
        const currentCount = countDoc.exists ? countData?.count || 0 : 0;
        const newCount = Math.max(0, currentCount - 1);
        transaction.set(countRef, {count: newCount}, {merge: true});
      }

      return {
        identityKey: userData.identityKey,
        signedPrekey: userData.signedPrekey,
        oneTimePrekey,
        registrationId: userData.registrationId || 0,
      };
    });
  }
);
