import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {RATE_LIMITS} from "../config/constants";

interface MessageRateLimitRequest {
  conversationId: string;
  recipientId: string;
}

interface MessageRateLimitResponse {
  allowed: boolean;
  retryAfterMs?: number;
  remainingMinute?: number;
  remainingHour?: number;
}

export const checkMessageRateLimit = onCall<MessageRateLimitRequest>(
  {
    enforceAppCheck: false,
    maxInstances: 10,
  },
  async (request): Promise<MessageRateLimitResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const userId = request.auth.uid;
    const {conversationId, recipientId} = request.data;

    if (!conversationId || !recipientId) {
      throw new HttpsError(
        "invalid-argument",
        "conversationId and recipientId are required"
      );
    }

    const db = admin.firestore();
    const config = RATE_LIMITS.MESSAGE;
    const now = admin.firestore.Timestamp.now();

    try {
      return await db.runTransaction(async (transaction) => {
              const userRateLimitRef = db.collection("message_rate_limits").doc(userId);
              const convRateLimitRef = db
                .collection("message_rate_limits")
                .doc(`${userId}_${conversationId}`);
      
              const [userDoc, convDoc] = await Promise.all([
                transaction.get(userRateLimitRef),
                transaction.get(convRateLimitRef),
              ]);
      
              const hourAgo = new Date(now.toMillis() - 60 * 60 * 1000);
              const minuteAgo = new Date(now.toMillis() - 60 * 1000);
      
              let userAttempts: admin.firestore.Timestamp[] = [];
              if (userDoc.exists) {
                userAttempts = (userDoc.data()?.attempts || []) as admin.firestore.Timestamp[];
                userAttempts = userAttempts.filter(
                  (timestamp: admin.firestore.Timestamp) => timestamp.toDate() > hourAgo
                );
              }
      
              let convAttempts: admin.firestore.Timestamp[] = [];
              if (convDoc.exists) {
                convAttempts = (convDoc.data()?.attempts || []) as admin.firestore.Timestamp[];
                convAttempts = convAttempts.filter(
                  (timestamp: admin.firestore.Timestamp) => timestamp.toDate() > hourAgo
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
      
              if (userAttemptsInMinute >= config.maxPerMinute) {
                const oldestInMinute = userAttempts
                  .filter((t: admin.firestore.Timestamp) => t.toDate() > minuteAgo)
                  .sort((a: admin.firestore.Timestamp, b: admin.firestore.Timestamp) =>
                    a.toMillis() - b.toMillis()
                  )[0];
                if (oldestInMinute) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldestInMinute.toMillis() + 60000 - now.toMillis()
                  );
                }
                limitReason = "global minute limit";
              }
      
              if (userAttemptsInHour >= config.maxPerHour) {
                const oldestInHour = userAttempts
                  .sort((a: admin.firestore.Timestamp, b: admin.firestore.Timestamp) =>
                    a.toMillis() - b.toMillis()
                  )[0];
                if (oldestInHour) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldestInHour.toMillis() + 3600000 - now.toMillis()
                  );
                }
                limitReason = "global hour limit";
              }
      
              if (convAttemptsInMinute >= config.conversationMaxPerMinute) {
                const oldestInMinute = convAttempts
                  .filter((t: admin.firestore.Timestamp) => t.toDate() > minuteAgo)
                  .sort((a: admin.firestore.Timestamp, b: admin.firestore.Timestamp) =>
                    a.toMillis() - b.toMillis()
                  )[0];
                if (oldestInMinute) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldestInMinute.toMillis() + 60000 - now.toMillis()
                  );
                }
                limitReason = "conversation minute limit";
              }
      
              if (convAttemptsInHour >= config.conversationMaxPerHour) {
                const oldestInHour = convAttempts
                  .sort((a: admin.firestore.Timestamp, b: admin.firestore.Timestamp) =>
                    a.toMillis() - b.toMillis()
                  )[0];
                if (oldestInHour) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldestInHour.toMillis() + 3600000 - now.toMillis()
                  );
                }
                limitReason = "conversation hour limit";
              }
      
              if (retryAfterMs > 0) {
                logger.warn("Message rate limit exceeded", {
                  userId,
                  conversationId,
                  limitReason,
                  userAttemptsInMinute,
                  userAttemptsInHour,
                  convAttemptsInMinute,
                  convAttemptsInHour,
                });
      
                return {
                  allowed: false,
                  retryAfterMs: Math.ceil(retryAfterMs),
                  remainingMinute: 0,
                  remainingHour: Math.max(
                    0,
                    config.maxPerHour - userAttemptsInHour,
                    config.conversationMaxPerHour - convAttemptsInHour
                  ),
                };
              }
      
              userAttempts.push(now);
              convAttempts.push(now);
      
              transaction.set(
                userRateLimitRef,
                {
                  attempts: userAttempts,
                  lastAttempt: now,
                  userId: userId,
                },
                {merge: true}
              );
      
              transaction.set(
                convRateLimitRef,
                {
                  attempts: convAttempts,
                  lastAttempt: now,
                  conversationId: conversationId,
                  userId: userId,
                  recipientId: recipientId,
                },
                {merge: true}
              );
      
              return {
                allowed: true,
                remainingMinute: Math.min(
                  config.maxPerMinute - userAttemptsInMinute - 1,
                  config.conversationMaxPerMinute - convAttemptsInMinute - 1
                ),
                remainingHour: Math.min(
                  config.maxPerHour - userAttemptsInHour - 1,
                  config.conversationMaxPerHour - convAttemptsInHour - 1
                ),
              };
            });
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error("Message rate limit check failed", {userId, errorMessage});
      throw new HttpsError("internal", "Rate limit check failed");
    }
  }
);
