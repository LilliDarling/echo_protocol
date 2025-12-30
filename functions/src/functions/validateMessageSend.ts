import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {REPLAY_PROTECTION, RATE_LIMITS} from "../config/constants.js";
import {db} from "../firebase.js";
import {
  ValidateMessageRequest,
  ValidateMessageResponse,
} from "../types/message.js";

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
    // TODO: Re-enable after configuring AppCheck on client
    // enforceAppCheck: true,
    maxInstances: 10,
    cors: true,
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

    const now = Date.now();
    const nowTimestamp = Timestamp.now();
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
      return await db.runTransaction(async (transaction) => {
        const userRateLimitRef = db
          .collection("message_rate_limits")
          .doc(senderId);
        const convRateLimitRef = db
          .collection("message_rate_limits")
          .doc(`${senderId}_${conversationId}`);

        const nonceRef = db.collection("message_nonces").doc(messageId);
        const sequenceRef = db
          .collection("message_sequences")
          .doc(`${senderId}_${conversationKey}`);
        const tokenRef = db.collection("message_tokens").doc();

        const [userDoc, convDoc, nonceDoc, sequenceDoc] = await Promise.all([
          transaction.get(userRateLimitRef),
          transaction.get(convRateLimitRef),
          transaction.get(nonceRef),
          transaction.get(sequenceRef),
        ]);

        const hourAgo = new Date(nowTimestamp.toMillis() - 60 * 60 * 1000);
        const minuteAgo = new Date(nowTimestamp.toMillis() - 60 * 1000);

        let userAttempts: Timestamp[] = [];
        if (userDoc.exists) {
          const data = userDoc.data();
          userAttempts = (data?.attempts || []) as Timestamp[];
          userAttempts = userAttempts.filter(
            (ts: Timestamp) => ts.toDate() > hourAgo
          );
        }

        let convAttempts: Timestamp[] = [];
        if (convDoc.exists) {
          const data = convDoc.data();
          convAttempts = (data?.attempts || []) as Timestamp[];
          convAttempts = convAttempts.filter(
            (ts: Timestamp) => ts.toDate() > hourAgo
          );
        }

        const userAttemptsInMinute = userAttempts.filter(
          (t: Timestamp) => t.toDate() > minuteAgo
        ).length;
        const userAttemptsInHour = userAttempts.length;

        const convAttemptsInMinute = convAttempts.filter(
          (t: Timestamp) => t.toDate() > minuteAgo
        ).length;
        const convAttemptsInHour = convAttempts.length;

        let retryAfterMs = 0;
        let limitReason = "";

        if (userAttemptsInMinute >= rateLimitConfig.maxPerMinute) {
                type TS = Timestamp;
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
                type TS = Timestamp;
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
                type TS = Timestamp;
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
                type TS = Timestamp;
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

        const maxGap = 1000;
        if (sequenceNumber > lastSequence + maxGap) {
          logger.warn("Sequence number gap too large", {
            senderId,
            messageId,
            sequenceNumber,
            lastSequence,
            gap: sequenceNumber - lastSequence,
          });
          return {valid: false, error: "Invalid sequence number"};
        }

        const token = tokenRef.id;
        const expiresAt = Timestamp.fromMillis(now + 30000);
        const nonceExpireAt = Timestamp.fromMillis(
          now + maxAge + 60000
        );
        const tokenExpireAt = Timestamp.fromMillis(
          now + 60 * 60 * 1000
        );
        const rateLimitExpireAt = Timestamp.fromMillis(
          nowTimestamp.toMillis() + 2 * 60 * 60 * 1000
        );

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

        transaction.set(nonceRef, {
          senderId,
          conversationId,
          timestamp: Timestamp.fromMillis(messageTime),
          createdAt: FieldValue.serverTimestamp(),
          expireAt: nonceExpireAt,
        });

        const sequenceExpireAt = Timestamp.fromMillis(
          now + 30 * 24 * 60 * 60 * 1000
        );

        transaction.set(
          sequenceRef,
          {
            lastSequence: sequenceNumber,
            updatedAt: FieldValue.serverTimestamp(),
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
          createdAt: FieldValue.serverTimestamp(),
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
