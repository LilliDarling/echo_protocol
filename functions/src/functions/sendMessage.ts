import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {REPLAY_PROTECTION, RATE_LIMITS} from "../config/constants.js";
import {db} from "../firebase.js";
import {SendMessageRequest, SendMessageResponse} from "../types/message.js";

/**
 * Generate a consistent conversation key from two user IDs
 * @param {string} id1 - First user ID
 * @param {string} id2 - Second user ID
 * @return {string} Sorted concatenation of user IDs
 */
function getConversationKey(id1: string, id2: string): string {
  return [id1, id2].sort().join("_");
}

/**
 * sendMessage - Validates and writes a message in a single atomic operation.
 *
 * This eliminates the need for token-based validation in security rules,
 * which required an expensive get() call. The Cloud Function handles:
 * - Rate limiting (per-user and per-conversation)
 * - Replay protection (nonce and sequence number validation)
 * - Message writing via Admin SDK
 *
 * Security: Admin SDK bypasses security rules, so all validation happens here.
 */
export const sendMessage = onCall<SendMessageRequest>(
  {
    // TODO: Re-enable after configuring AppCheck on client
    // enforceAppCheck: true,
    maxInstances: 20,
    cors: true,
  },
  async (request): Promise<SendMessageResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const senderId = request.auth.uid;
    const {
      messageId,
      conversationId,
      recipientId,
      content,
      sequenceNumber,
      timestamp,
      senderKeyVersion,
      recipientKeyVersion,
      type,
      metadata,
      mediaType,
      mediaUrl,
      thumbnailUrl,
    } = request.data;

    if (!messageId || !conversationId || !recipientId || !content) {
      throw new HttpsError(
        "invalid-argument",
        "messageId, conversationId, recipientId, and content are required"
      );
    }

    if (typeof content !== "string" || content.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Content must be a non-empty string"
      );
    }

    if (content.length > 100000) {
      throw new HttpsError(
        "invalid-argument",
        "Content exceeds maximum length"
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

    if (typeof senderKeyVersion !== "number" || senderKeyVersion < 1) {
      throw new HttpsError(
        "invalid-argument",
        "senderKeyVersion is required"
      );
    }

    if (typeof recipientKeyVersion !== "number" || recipientKeyVersion < 1) {
      throw new HttpsError(
        "invalid-argument",
        "recipientKeyVersion is required"
      );
    }

    const now = Date.now();
    const nowTimestamp = Timestamp.now();
    const messageTime = timestamp;

    const maxAge = REPLAY_PROTECTION.nonceExpiryHours * 60 * 60 * 1000;
    const clockSkew = REPLAY_PROTECTION.clockSkewToleranceMinutes * 60 * 1000;

    if (now - messageTime > maxAge) {
      logger.warn("Message timestamp too old", {senderId, messageId});
      return {success: false, error: "Message timestamp expired"};
    }

    if (messageTime - now > clockSkew) {
      logger.warn("Message timestamp in future", {senderId, messageId});
      return {success: false, error: "Message timestamp in future"};
    }

    const conversationKey = getConversationKey(senderId, recipientId);
    const rateLimitConfig = RATE_LIMITS.MESSAGE;

    try {
      return await db.runTransaction(async (transaction) => {
        const convRef = db.collection("conversations").doc(conversationId);
        const convDoc = await transaction.get(convRef);

        if (!convDoc.exists) {
          throw new HttpsError("not-found", "Conversation not found");
        }

        const participants = convDoc.data()?.participants as string[];
        const isSenderInConv = participants.includes(senderId);
        const isRecipientInConv = participants.includes(recipientId);
        if (!isSenderInConv || !isRecipientInConv) {
          throw new HttpsError(
            "permission-denied",
            "Not a conversation participant"
          );
        }

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

        const messageRef = convRef.collection("messages").doc(messageId);

        const [userDoc, convRateDoc, nonceDoc, sequenceDoc, existingMsg] =
                await Promise.all([
                  transaction.get(userRateLimitRef),
                  transaction.get(convRateLimitRef),
                  transaction.get(nonceRef),
                  transaction.get(sequenceRef),
                  transaction.get(messageRef),
                ]);

        if (existingMsg.exists) {
          logger.warn("Message already exists", {senderId, messageId});
          return {success: false, error: "Message already exists"};
        }

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
        if (convRateDoc.exists) {
          const data = convRateDoc.data();
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
                const oldest = userAttempts
                  .filter((t: TS) => t.toDate() > minuteAgo)
                  .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
                if (oldest) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldest.toMillis() + 60000 - nowTimestamp.toMillis()
                  );
                }
                limitReason = "global minute limit";
        }

        if (userAttemptsInHour >= rateLimitConfig.maxPerHour) {
                type TS = Timestamp;
                const oldest = userAttempts
                  .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
                if (oldest) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldest.toMillis() + 3600000 - nowTimestamp.toMillis()
                  );
                }
                limitReason = "global hour limit";
        }

        if (convAttemptsInMinute >= rateLimitConfig.conversationMaxPerMinute) {
                type TS = Timestamp;
                const oldest = convAttempts
                  .filter((t: TS) => t.toDate() > minuteAgo)
                  .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
                if (oldest) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldest.toMillis() + 60000 - nowTimestamp.toMillis()
                  );
                }
                limitReason = "conversation minute limit";
        }

        if (convAttemptsInHour >= rateLimitConfig.conversationMaxPerHour) {
                type TS = Timestamp;
                const oldest = convAttempts
                  .sort((a: TS, b: TS) => a.toMillis() - b.toMillis())[0];
                if (oldest) {
                  retryAfterMs = Math.max(
                    retryAfterMs,
                    oldest.toMillis() + 3600000 - nowTimestamp.toMillis()
                  );
                }
                limitReason = "conversation hour limit";
        }

        if (retryAfterMs > 0) {
          logger.warn("Message rate limit exceeded", {
            userId: senderId,
            conversationId,
            limitReason,
          });

          return {
            success: false,
            error: "Rate limit exceeded",
            retryAfterMs: Math.ceil(retryAfterMs),
            remainingMinute: 0,
            remainingHour: 0,
          };
        }

        if (nonceDoc.exists) {
          logger.warn("Duplicate nonce detected (replay attack)", {
            senderId,
            messageId,
          });
          return {success: false, error: "Duplicate message ID"};
        }

        const lastSequence = (sequenceDoc.data()?.lastSequence as number) || 0;
        if (sequenceNumber <= lastSequence) {
          logger.warn("Invalid sequence number", {
            senderId,
            messageId,
            sequenceNumber,
            lastSequence,
          });
          return {success: false, error: "Invalid sequence number"};
        }

        const maxGap = 1000;
        if (sequenceNumber > lastSequence + maxGap) {
          logger.warn("Sequence gap too large", {senderId, sequenceNumber});
          return {success: false, error: "Invalid sequence number"};
        }

        const rateLimitExpireAt = Timestamp.fromMillis(
          nowTimestamp.toMillis() + 2 * 60 * 60 * 1000
        );
        const nonceExpireAt = Timestamp.fromMillis(
          now + maxAge + 60000
        );
        const sequenceExpireAt = Timestamp.fromMillis(
          now + 30 * 24 * 60 * 60 * 1000
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

        transaction.set(
          sequenceRef,
          {
            lastSequence: sequenceNumber,
            updatedAt: FieldValue.serverTimestamp(),
            expireAt: sequenceExpireAt,
          },
          {merge: true}
        );

        const messageData: Record<string, unknown> = {
          content,
          senderId,
          recipientId,
          timestamp: Timestamp.fromMillis(messageTime),
          senderKeyVersion,
          recipientKeyVersion,
          sequenceNumber,
          type: type || "text",
          metadata: metadata || {},
          status: "sent",
          createdAt: FieldValue.serverTimestamp(),
          isEdited: false,
          isDeleted: false,
          encryptionVersion: 2,
        };

        if (mediaType) messageData.mediaType = mediaType;
        if (mediaUrl) messageData.mediaUrl = mediaUrl;
        if (thumbnailUrl) messageData.thumbnailUrl = thumbnailUrl;

        transaction.set(messageRef, messageData);

        transaction.update(convRef, {
          lastMessage: content.substring(0, 100),
          lastMessageAt: FieldValue.serverTimestamp(),
        });

        return {
          success: true,
          messageId,
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
      logger.error("Message send failed", {senderId, errorMessage});
      throw new HttpsError("internal", "Failed to send message");
    }
  }
);
