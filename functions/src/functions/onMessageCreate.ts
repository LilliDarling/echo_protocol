import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export const onMessageCreate = onDocumentCreated(
  "messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const messageData = snapshot.data();
    const messageId = event.params.messageId;

    const {senderId, validationToken} = messageData;

    if (!validationToken) {
      logger.error("Message missing validation token", {messageId, senderId});
      await snapshot.ref.delete();
      return;
    }

    const db = admin.firestore();

    try {
      const tokenRef = db.collection("message_tokens").doc(validationToken);
      const tokenDoc = await tokenRef.get();

      if (!tokenDoc.exists) {
        logger.error("Invalid validation token", {
          messageId,
          senderId,
          token: validationToken,
        });
        await snapshot.ref.delete();
        return;
      }

      const tokenData = tokenDoc.data()!;

      if (tokenData.used) {
        logger.error("Validation token already used (replay attempt)", {
          messageId,
          senderId,
          token: validationToken,
        });
        await snapshot.ref.delete();
        return;
      }

      if (tokenData.messageId !== messageId) {
        logger.error("Token messageId mismatch", {
          messageId,
          tokenMessageId: tokenData.messageId,
          senderId,
        });
        await snapshot.ref.delete();
        return;
      }

      if (tokenData.senderId !== senderId) {
        logger.error("Token senderId mismatch", {
          messageId,
          messageSenderId: senderId,
          tokenSenderId: tokenData.senderId,
        });
        await snapshot.ref.delete();
        return;
      }

      const now = admin.firestore.Timestamp.now();
      if (tokenData.expiresAt.toMillis() < now.toMillis()) {
        logger.error("Validation token expired", {
          messageId,
          senderId,
          expiresAt: tokenData.expiresAt.toDate(),
        });
        await snapshot.ref.delete();
        return;
      }

      await tokenRef.update({
        used: true,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await snapshot.ref.update({
        serverValidated: true,
        validatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error("Message validation trigger failed", {
        messageId,
        senderId,
        errorMessage,
      });
      await snapshot.ref.delete();
    }
  }
);
