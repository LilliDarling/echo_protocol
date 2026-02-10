import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {db} from "../firebase.js";
import {DeliverMessageRequest, DeliverMessageResponse} from "../types/inbox.js";

const RATE_LIMITS = {
  maxPerMinute: 30,
  maxPerHour: 500,
};

const INBOX_TTL_DAYS = 7;

function getConversationKey(id1: string, id2: string): string {
  return [id1, id2].sort().join("_");
}

export const deliverMessage = onCall<DeliverMessageRequest>(
  {
    maxInstances: 20,
    cors: true,
  },
  async (request): Promise<DeliverMessageResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const senderId = request.auth.uid;
    const {messageId, recipientId, sealedEnvelope, sequenceNumber} = request.data;

    if (!messageId || typeof messageId !== "string") {
      throw new HttpsError("invalid-argument", "messageId is required");
    }

    if (!recipientId || typeof recipientId !== "string") {
      throw new HttpsError("invalid-argument", "recipientId is required");
    }

    if (recipientId === senderId) {
      throw new HttpsError("invalid-argument", "Cannot send to yourself");
    }

    if (!sealedEnvelope || !sealedEnvelope.payload || !sealedEnvelope.ephemeralKey) {
      throw new HttpsError("invalid-argument", "sealedEnvelope is required");
    }

    if (typeof sealedEnvelope.payload !== "string" || sealedEnvelope.payload.length === 0) {
      throw new HttpsError("invalid-argument", "Invalid envelope payload");
    }

    if (sealedEnvelope.payload.length > 200000) {
      throw new HttpsError("invalid-argument", "Payload exceeds maximum size");
    }

    if (typeof sequenceNumber !== "number" || sequenceNumber < 1) {
      throw new HttpsError("invalid-argument", "sequenceNumber must be positive");
    }

    const conversationKey = getConversationKey(senderId, recipientId);
    const now = Timestamp.now();

    try {
      const result = await db.runTransaction(async (transaction) => {
        const senderRef = db.collection("users").doc(senderId);
        const senderDoc = await transaction.get(senderRef);

        if (!senderDoc.exists) {
          throw new HttpsError("not-found", "Sender not found");
        }

        const senderData = senderDoc.data();
        if (senderData?.partnerId !== recipientId) {
          throw new HttpsError(
            "permission-denied",
            "Not linked to recipient"
          );
        }

        const recipientRef = db.collection("users").doc(recipientId);
        const recipientDoc = await transaction.get(recipientRef);

        if (!recipientDoc.exists) {
          throw new HttpsError("not-found", "Recipient not found");
        }

        const recipientData = recipientDoc.data();
        if (recipientData?.partnerId !== senderId) {
          throw new HttpsError(
            "permission-denied",
            "Recipient not linked to sender"
          );
        }

        const rateLimitRef = db.collection("inbox_rate_limits").doc(senderId);
        const rateLimitDoc = await transaction.get(rateLimitRef);

        const hourAgo = new Date(now.toMillis() - 60 * 60 * 1000);
        const minuteAgo = new Date(now.toMillis() - 60 * 1000);

        let attempts: Timestamp[] = [];
        if (rateLimitDoc.exists) {
          const data = rateLimitDoc.data();
          attempts = (data?.attempts || []) as Timestamp[];
          attempts = attempts.filter((ts: Timestamp) => ts.toDate() > hourAgo);
        }

        const attemptsInMinute = attempts.filter(
          (t: Timestamp) => t.toDate() > minuteAgo
        ).length;
        const attemptsInHour = attempts.length;

        if (attemptsInMinute >= RATE_LIMITS.maxPerMinute) {
          const oldest = attempts
            .filter((t: Timestamp) => t.toDate() > minuteAgo)
            .sort((a: Timestamp, b: Timestamp) => a.toMillis() - b.toMillis())[0];
          const retryAfterMs = oldest ?
            oldest.toMillis() + 60000 - now.toMillis() : 60000;

          return {
            success: false,
            error: "Rate limit exceeded",
            retryAfterMs: Math.ceil(retryAfterMs),
          };
        }

        if (attemptsInHour >= RATE_LIMITS.maxPerHour) {
          const oldest = attempts
            .sort((a: Timestamp, b: Timestamp) => a.toMillis() - b.toMillis())[0];
          const retryAfterMs = oldest ?
            oldest.toMillis() + 3600000 - now.toMillis() : 3600000;

          return {
            success: false,
            error: "Rate limit exceeded",
            retryAfterMs: Math.ceil(retryAfterMs),
          };
        }

        const nonceRef = db.collection("inbox_nonces").doc(messageId);
        const nonceDoc = await transaction.get(nonceRef);

        if (nonceDoc.exists) {
          logger.warn("Duplicate message detected");
          return {success: false, error: "Duplicate message"};
        }

        const sequenceRef = db
          .collection("inbox_sequences")
          .doc(`${senderId}_${conversationKey}`);
        const sequenceDoc = await transaction.get(sequenceRef);

        const lastSequence = (sequenceDoc.data()?.lastSequence as number) || 0;
        if (sequenceNumber <= lastSequence) {
          logger.warn("Invalid sequence number");
          return {success: false, error: "Invalid sequence"};
        }

        const maxGap = 1000;
        if (sequenceNumber > lastSequence + maxGap) {
          logger.warn("Sequence gap too large");
          return {success: false, error: "Invalid sequence"};
        }

        const inboxRef = db
          .collection("inboxes")
          .doc(recipientId)
          .collection("pending")
          .doc(messageId);

        const existingMsg = await transaction.get(inboxRef);
        if (existingMsg.exists) {
          return {success: false, error: "Message already exists"};
        }

        const expireAt = Timestamp.fromMillis(
          now.toMillis() + INBOX_TTL_DAYS * 24 * 60 * 60 * 1000
        );

        transaction.set(inboxRef, {
          sealedEnvelope: {
            payload: sealedEnvelope.payload,
            ephemeralKey: sealedEnvelope.ephemeralKey,
            timestamp: sealedEnvelope.timestamp,
            expireAt: sealedEnvelope.expireAt,
          },
          deliveredAt: FieldValue.serverTimestamp(),
          expireAt: expireAt,
          isOutgoing: false,
        });

        attempts.push(now);
        transaction.set(
          rateLimitRef,
          {
            attempts: attempts,
            lastAttempt: now,
            expireAt: Timestamp.fromMillis(now.toMillis() + 2 * 60 * 60 * 1000),
          },
          {merge: true}
        );

        transaction.set(nonceRef, {
          deliveredAt: FieldValue.serverTimestamp(),
          expireAt: Timestamp.fromMillis(now.toMillis() + 60 * 60 * 1000),
        });

        transaction.set(
          sequenceRef,
          {
            lastSequence: sequenceNumber,
            updatedAt: FieldValue.serverTimestamp(),
            expireAt: Timestamp.fromMillis(now.toMillis() + 30 * 24 * 60 * 60 * 1000),
          },
          {merge: true}
        );

        return {success: true, messageId};
      });

      if (result.success) {
        logger.info("Message delivered to inbox");
      }

      return result;
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("Delivery failed");
      throw new HttpsError("internal", "Failed to deliver message");
    }
  }
);
