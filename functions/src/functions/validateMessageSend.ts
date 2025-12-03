import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {REPLAY_PROTECTION} from "../config/constants";

interface ValidateMessageRequest {
  messageId: string;
  conversationId: string;
  recipientId: string;
  sequenceNumber: number;
  timestamp: number;
}

interface ValidateMessageResponse {
  valid: boolean;
  token?: string;
  error?: string;
}

function getConversationKey(userId1: string, userId2: string): string {
  return [userId1, userId2].sort().join("_");
}

export const validateMessageSend = onCall<ValidateMessageRequest>(
  {
    enforceAppCheck: false,
    maxInstances: 10,
  },
  async (request): Promise<ValidateMessageResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const senderId = request.auth.uid;
    const {messageId, conversationId, recipientId, sequenceNumber, timestamp} =
      request.data;

    if (!messageId || !conversationId || !recipientId) {
      throw new HttpsError(
        "invalid-argument",
        "messageId, conversationId, and recipientId are required"
      );
    }

    if (typeof sequenceNumber !== "number" || sequenceNumber < 1) {
      throw new HttpsError(
        "invalid-argument",
        "sequenceNumber must be a positive integer"
      );
    }

    if (typeof timestamp !== "number") {
      throw new HttpsError("invalid-argument", "timestamp is required");
    }

    const db = admin.firestore();
    const now = Date.now();
    const messageTime = timestamp;

    const maxAge = REPLAY_PROTECTION.nonceExpiryHours * 60 * 60 * 1000;
    const clockSkew = REPLAY_PROTECTION.clockSkewToleranceMinutes * 60 * 1000;

    if (now - messageTime > maxAge) {
      logger.warn("Message timestamp too old", {
        senderId,
        messageId,
        age: now - messageTime,
      });
      return {valid: false, error: "Message timestamp expired"};
    }

    if (messageTime - now > clockSkew) {
      logger.warn("Message timestamp in future", {
        senderId,
        messageId,
        drift: messageTime - now,
      });
      return {valid: false, error: "Message timestamp in future"};
    }

    const conversationKey = getConversationKey(senderId, recipientId);

    try {
      const result = await db.runTransaction(async (transaction) => {
        const nonceRef = db.collection("message_nonces").doc(messageId);
        const sequenceRef = db
          .collection("message_sequences")
          .doc(`${senderId}_${conversationKey}`);
        const tokenRef = db.collection("message_tokens").doc();

        const [nonceDoc, sequenceDoc] = await Promise.all([
          transaction.get(nonceRef),
          transaction.get(sequenceRef),
        ]);

        if (nonceDoc.exists) {
          logger.warn("Duplicate nonce detected (replay attack)", {
            senderId,
            messageId,
            conversationId,
          });
          return {valid: false, error: "Duplicate message ID"};
        }

        const lastSequence = (sequenceDoc.data()?.lastSequence as number) || 0;
        if (sequenceNumber <= lastSequence) {
          logger.warn("Invalid sequence number (replay/reorder attack)", {
            senderId,
            messageId,
            sequenceNumber,
            lastSequence,
          });
          return {valid: false, error: "Invalid sequence number"};
        }

        const token = tokenRef.id;
        const expiresAt = admin.firestore.Timestamp.fromMillis(now + 30000);
        const nonceExpireAt = admin.firestore.Timestamp.fromMillis(
          now + maxAge + 60000
        );
        const tokenExpireAt = admin.firestore.Timestamp.fromMillis(
          now + 60 * 60 * 1000
        );

        transaction.set(nonceRef, {
          senderId,
          conversationId,
          timestamp: admin.firestore.Timestamp.fromMillis(messageTime),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: nonceExpireAt,
        });

        transaction.set(
          sequenceRef,
          {
            lastSequence: sequenceNumber,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        transaction.set(tokenRef, {
          messageId,
          senderId,
          conversationId,
          recipientId,
          sequenceNumber,
          expiresAt,
          used: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: tokenExpireAt,
        });

        return {valid: true, token};
      });

      return result;
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error("Message validation failed", {senderId, errorMessage});
      throw new HttpsError("internal", "Validation failed");
    }
  }
);
