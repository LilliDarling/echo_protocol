import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {REPLAY_PROTECTION, RATE_LIMITS} from "../config/constants";

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
  retryAfterMs?: number;
  remainingMinute?: number;
  remainingHour?: number;
}

/**
 * Generate a consistent conversation key from two user IDs
 * @param {string} userId1 - First user ID
 * @param {string} userId2 - Second user ID
 * @return {string} Sorted concatenation of user IDs
 */
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
    const nowTimestamp = admin.firestore.Timestamp.now();
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
    const rateLimitConfig = RATE_LIMITS.MESSAGE;

    try {
      const result = await db.runTransaction(async (transaction) => {
        // Rate limit refs
        const userRateLimitRef = db
          .collection("message_rate_limits")
          .doc(senderId);
        const convRateLimitRef = db
          .collection("message_rate_limits")
          .doc(`${senderId}_${conversationId}`);

        // Replay protection refs
        const nonceRef = db.collection("message_nonces").doc(messageId);
        const sequenceRef = db
          .collection("message_sequences")
          .doc(`${senderId}_${conversationKey}`);
        const tokenRef = db.collection("message_tokens").doc();

        // Fetch all documents
        const [userDoc, convDoc, nonceDoc, sequenceDoc] = await Promise.all([
          transaction.get(userRateLimitRef),
          transaction.get(convRateLimitRef),
          transaction.get(nonceRef),
          transaction.get(sequenceRef),
        ]);

        // --- Rate Limiting Check ---
        const hourAgo = new Date(nowTimestamp.toMillis() - 60 * 60 * 1000);
        const minuteAgo = new Date(nowTimestamp.toMillis() - 60 * 1000);

        let userAttempts: admin.firestore.Timestamp[] = [];
        if (userDoc.exists) {
          userAttempts =
            (userDoc.data()?.attempts || []) as admin.firestore.Timestamp[];
          userAttempts = userAttempts.filter(
            (ts: admin.firestore.Timestamp) => ts.toDate() > hourAgo
          );
        }

        let convAttempts: admin.firestore.Timestamp[] = [];
        if (convDoc.exists) {
          convAttempts =
            (convDoc.data()?.attempts || []) as admin.firestore.Timestamp[];
          convAttempts = convAttempts.filter(
            (ts: admin.firestore.Timestamp) => ts.toDate() > hourAgo
          );
        }

        const userAttemptsInMinute = userAttempts.filter(
          (t: admin.firestore.Timestamp) => t.toDate() > minuteAgo
        ).length;
        const userAttemptsInHour = userAttempts.length;

        const convAttemptsInMinute = convAttempts.filter(
          (t: admin.firestore.Timestamp) => t.toDate() > minuteAgo
        ).length;
        const convAttemptsInHour = convAttempts.length;

        let retryAfterMs = 0;
        let limitReason = "";

        if (userAttemptsInMinute >= rateLimitConfig.maxPerMinute) {
          type TS = admin.firestore.Timestamp;
          const oldestInMinute = userAttempts
            .filter((t: TS) => t.toDate() > minuteAgo)
            .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
          if (oldestInMinute) {
            retryAfterMs = Math.max(
              retryAfterMs,
              oldestInMinute.toMillis() + 60000 - nowTimestamp.toMillis()
            );
          }
          limitReason = "global minute limit";
        }

        if (userAttemptsInHour >= rateLimitConfig.maxPerHour) {
          type TS = admin.firestore.Timestamp;
          const oldestInHour = userAttempts
            .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
          if (oldestInHour) {
            retryAfterMs = Math.max(
              retryAfterMs,
              oldestInHour.toMillis() + 3600000 - nowTimestamp.toMillis()
            );
          }
          limitReason = "global hour limit";
        }

        if (convAttemptsInMinute >= rateLimitConfig.conversationMaxPerMinute) {
          type TS = admin.firestore.Timestamp;
          const oldestInMinute = convAttempts
            .filter((t: TS) => t.toDate() > minuteAgo)
            .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
          if (oldestInMinute) {
            retryAfterMs = Math.max(
              retryAfterMs,
              oldestInMinute.toMillis() + 60000 - nowTimestamp.toMillis()
            );
          }
          limitReason = "conversation minute limit";
        }

        if (convAttemptsInHour >= rateLimitConfig.conversationMaxPerHour) {
          type TS = admin.firestore.Timestamp;
          const oldestInHour = convAttempts
            .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
          if (oldestInHour) {
            retryAfterMs = Math.max(
              retryAfterMs,
              oldestInHour.toMillis() + 3600000 - nowTimestamp.toMillis()
            );
          }
          limitReason = "conversation hour limit";
        }

        if (retryAfterMs > 0) {
          logger.warn("Message rate limit exceeded", {
            userId: senderId,
            conversationId,
            limitReason,
            userAttemptsInMinute,
            userAttemptsInHour,
            convAttemptsInMinute,
            convAttemptsInHour,
          });

          return {
            valid: false,
            error: "Rate limit exceeded",
            retryAfterMs: Math.ceil(retryAfterMs),
            remainingMinute: 0,
            remainingHour: Math.max(
              0,
              rateLimitConfig.maxPerHour - userAttemptsInHour,
              rateLimitConfig.conversationMaxPerHour - convAttemptsInHour
            ),
          };
        }

        // --- Replay Protection Check ---
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

        // --- All checks passed, write updates ---
        const token = tokenRef.id;
        const expiresAt = admin.firestore.Timestamp.fromMillis(now + 30000);
        const nonceExpireAt = admin.firestore.Timestamp.fromMillis(
          now + maxAge + 60000
        );
        const tokenExpireAt = admin.firestore.Timestamp.fromMillis(
          now + 60 * 60 * 1000
        );
        const rateLimitExpireAt = admin.firestore.Timestamp.fromMillis(
          nowTimestamp.toMillis() + 2 * 60 * 60 * 1000
        );

        // Update rate limit tracking
        userAttempts.push(nowTimestamp);
        convAttempts.push(nowTimestamp);

        transaction.set(
          userRateLimitRef,
          {
            attempts: userAttempts,
            lastAttempt: nowTimestamp,
            userId: senderId,
            expireAt: rateLimitExpireAt,
          },
          {merge: true}
        );

        transaction.set(
          convRateLimitRef,
          {
            attempts: convAttempts,
            lastAttempt: nowTimestamp,
            conversationId: conversationId,
            userId: senderId,
            recipientId: recipientId,
            expireAt: rateLimitExpireAt,
          },
          {merge: true}
        );

        // Write replay protection data
        transaction.set(nonceRef, {
          senderId,
          conversationId,
          timestamp: admin.firestore.Timestamp.fromMillis(messageTime),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: nonceExpireAt,
        });

        const sequenceExpireAt = admin.firestore.Timestamp.fromMillis(
          now + 30 * 24 * 60 * 60 * 1000
        );

        transaction.set(
          sequenceRef,
          {
            lastSequence: sequenceNumber,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            expireAt: sequenceExpireAt,
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

        return {
          valid: true,
          token,
          remainingMinute: Math.min(
            rateLimitConfig.maxPerMinute - userAttemptsInMinute - 1,
            rateLimitConfig.conversationMaxPerMinute - convAttemptsInMinute - 1
          ),
          remainingHour: Math.min(
            rateLimitConfig.maxPerHour - userAttemptsInHour - 1,
            rateLimitConfig.conversationMaxPerHour - convAttemptsInHour - 1
          ),
        };
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
