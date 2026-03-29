import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {db} from "../firebase.js";
import {getStorage} from "firebase-admin/storage";
import {QueryDocumentSnapshot} from "firebase-admin/firestore";

const BATCH_SIZE = 200;

export const cleanupExpiredMedia = onSchedule(
  {
    schedule: "every day 03:00",
    timeZone: "UTC",
    memory: "256MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const now = Date.now();
    let deletedCount = 0;
    let errorCount = 0;

    logger.info("Starting vault media cleanup job");

    try {
      const bucket = getStorage().bucket();
      let lastDoc: QueryDocumentSnapshot | undefined;

      // eslint-disable-next-line no-constant-condition
      while (true) {
        let query = db.collectionGroup("media")
          .where("source", "==", "vault")
          .where("expireAt", "<=", now)
          .where("expireAt", ">", 0)
          .orderBy("expireAt")
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) break;

        for (const mediaDoc of snapshot.docs) {
          const data = mediaDoc.data();
          const storagePath = data.storagePath as string | undefined;

          try {
            if (storagePath) {
              await bucket.file(storagePath).delete().catch(() => {
                // File may already be deleted
              });
            }

            await mediaDoc.ref.delete();
            deletedCount++;
          } catch (err) {
            logger.error(`Failed to delete media ${mediaDoc.id}`, err);
            errorCount++;
          }
        }

        lastDoc = snapshot.docs[snapshot.docs.length - 1];

        // If we got fewer than BATCH_SIZE, we've reached the end
        if (snapshot.size < BATCH_SIZE) break;
      }

      logger.info(
        `Vault media cleanup complete: ${deletedCount} deleted, ${errorCount} errors`
      );
    } catch (err) {
      logger.error("Vault media cleanup job failed", err);
      throw err;
    }
  }
);
