import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import {db} from "../firebase.js";
import {getStorage} from "firebase-admin/storage";
import {FieldValue} from "firebase-admin/firestore";

const MAX_VAULT_CHUNKS = 10000;

export const enforceVaultQuota = onDocumentCreated(
  {
    document: "vaults/{userId}/chunks/{chunkId}",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (event) => {
    const userId = event.params.userId;
    const chunkId = event.params.chunkId;

    const vaultRef = db.collection("vaults").doc(userId);

    try {
      const newCount = await db.runTransaction(async (tx) => {
        const vaultDoc = await tx.get(vaultRef);
        const currentCount = vaultDoc.exists
          ? (vaultDoc.data()?.chunkCount as number ?? 0)
          : 0;

        if (currentCount >= MAX_VAULT_CHUNKS) {
          // Over quota — delete the chunk that triggered this
          tx.delete(
            vaultRef.collection("chunks").doc(chunkId)
          );
          return -1;
        }

        tx.set(
          vaultRef,
          {chunkCount: FieldValue.increment(1)},
          {merge: true}
        );

        return currentCount + 1;
      });

      if (newCount === -1) {
        // Clean up the orphaned Storage blob outside the transaction
        const storagePath = `vault_chunks/${userId}/${chunkId}.bin`;
        try {
          await getStorage().bucket().file(storagePath).delete();
        } catch (storageErr) {
          // File may not exist yet if client crashed between Firestore write and Storage upload
          logger.warn(
            `Failed to delete Storage blob ${storagePath}`, storageErr
          );
        }

        logger.warn(
          `Vault quota exceeded for user ${userId}, deleted chunk ${chunkId}`
        );
      }
    } catch (err) {
      logger.error(`Vault quota enforcement failed for ${userId}`, err);
    }
  }
);
