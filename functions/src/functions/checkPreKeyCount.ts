import {onCall, HttpsError} from "firebase-functions/v2/https";
import {CheckPreKeyCountResponse} from "../types/prekey.js";
import {db} from "../firebase.js";

const REPLENISH_THRESHOLD = 10;
const SIGNED_PREKEY_WARNING_DAYS = 7;

export const checkPreKeyCount = onCall(
  {
    // TODO: Re-enable after configuring AppCheck on client
    // enforceAppCheck: true,
    maxInstances: 10,
    cors: true,
  },
  async (request): Promise<CheckPreKeyCountResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const userId = request.auth.uid;
    const userRef = db.collection("users").doc(userId);

    const [userDoc, countDoc] = await Promise.all([
      userRef.get(),
      userRef.collection("metadata").doc("prekeyCount").get(),
    ]);

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found");
    }

    const userData = userDoc.data() ?? {};
    const countData = countDoc.data();
    const oneTimePrekeyCount = countDoc.exists ? countData?.count || 0 : 0;

    let signedPrekeyExpiresAt = 0;
    if (userData.signedPrekey?.expiresAt) {
      signedPrekeyExpiresAt = userData.signedPrekey.expiresAt;
    }

    const now = Date.now();
    const msPerDay = 24 * 60 * 60 * 1000;
    const warningMs = SIGNED_PREKEY_WARNING_DAYS * msPerDay;
    const warningThreshold = now + warningMs;
    const expiringSoon = signedPrekeyExpiresAt > 0 &&
      signedPrekeyExpiresAt < warningThreshold;

    const needsReplenishment =
      oneTimePrekeyCount < REPLENISH_THRESHOLD || expiringSoon;

    return {
      oneTimePrekeyCount,
      signedPrekeyExpiresAt,
      needsReplenishment,
      replenishThreshold: REPLENISH_THRESHOLD,
    };
  }
);
