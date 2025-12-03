import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {REPLAY_PROTECTION} from "../config/constants";

const BATCH_SIZE = 500;
const MAX_BATCHES_PER_RUN = 10;

async function deleteInBatches(
  query: FirebaseFirestore.Query,
  db: FirebaseFirestore.Firestore
): Promise<number> {
  let totalDeleted = 0;
  let batchCount = 0;

  while (batchCount < MAX_BATCHES_PER_RUN) {
    const snapshot = await query.limit(BATCH_SIZE).get();

    if (snapshot.empty) {
      break;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    totalDeleted += snapshot.size;
    batchCount++;

    if (snapshot.size < BATCH_SIZE) {
      break;
    }
  }

  return totalDeleted;
}

export const cleanupExpiredReplayData = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: "UTC",
    retryCount: 3,
    memory: "256MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const nonceExpiryMs = REPLAY_PROTECTION.nonceExpiryHours * 60 * 60 * 1000;
    const nonceCutoff = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - nonceExpiryMs
    );

    try {
      const noncesDeleted = await deleteInBatches(
        db.collection("message_nonces").where("createdAt", "<", nonceCutoff),
        db
      );

      const usedTokensDeleted = await deleteInBatches(
        db.collection("message_tokens").where("used", "==", true),
        db
      );

      const expiredTokensDeleted = await deleteInBatches(
        db.collection("message_tokens").where("expiresAt", "<", now),
        db
      );

      const sequenceCutoff = admin.firestore.Timestamp.fromMillis(
        now.toMillis() - 30 * 24 * 60 * 60 * 1000
      );
      const sequencesDeleted = await deleteInBatches(
        db.collection("message_sequences").where("updatedAt", "<", sequenceCutoff),
        db
      );

      const rateLimitCutoff = admin.firestore.Timestamp.fromMillis(
        now.toMillis() - 2 * 60 * 60 * 1000
      );
      const rateLimitsDeleted = await deleteInBatches(
        db.collection("message_rate_limits").where("lastAttempt", "<", rateLimitCutoff),
        db
      );

      logger.info("Replay data cleanup completed", {
        noncesDeleted,
        tokensDeleted: usedTokensDeleted + expiredTokensDeleted,
        sequencesDeleted,
        rateLimitsDeleted,
      });
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error("Replay data cleanup failed", {errorMessage});
      throw error;
    }
  }
);
