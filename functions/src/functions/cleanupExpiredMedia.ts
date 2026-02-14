import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {db} from "../firebase.js";
import {getStorage} from "firebase-admin/storage";

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
      const vaultsSnapshot = await db.collectionGroup("media")
        .where("expireAt", "<=", now)
        .where("expireAt", ">", 0)
        .get();

      if (vaultsSnapshot.empty) {
        logger.info("No expired vault media found");
        return;
      }

      logger.info(`Found ${vaultsSnapshot.size} expired media items`);

      const bucket = getStorage().bucket();

      for (const mediaDoc of vaultsSnapshot.docs) {
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

      logger.info(
        `Vault media cleanup complete: ${deletedCount} deleted, ${errorCount} errors`
      );
    } catch (err) {
      logger.error("Vault media cleanup job failed", err);
      throw err;
    }
  }
);
