import {db, messaging} from "../firebase.js";
import * as logger from "firebase-functions/logger";

interface NotificationData {
  recipientId: string;
  senderId: string;
  conversationId: string;
  messageType: string;
}

type PreviewLevel = "full" | "senderOnly" | "hidden";

export async function sendPushNotification(data: NotificationData): Promise<void> {
  const {recipientId, senderId, conversationId, messageType} = data;

  try {
    const recipientDoc = await db.collection("users").doc(recipientId).get();
    if (!recipientDoc.exists) return;

    const recipientData = recipientDoc.data();
    if (!recipientData) return;

    const prefs = recipientData.preferences as Record<string, unknown> | undefined;
    if (!prefs) return;

    const notificationsEnabled = prefs.notifications as boolean | undefined;
    if (notificationsEnabled === false) return;

    const fcmTokens = recipientData.fcmTokens as Record<string, string> | undefined;
    if (!fcmTokens || Object.keys(fcmTokens).length === 0) return;

    const previewLevel = (prefs.notificationPreview as PreviewLevel) || "senderOnly";

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderData = senderDoc.data();
    const senderName = (senderData?.name as string) || "Someone";

    const {title, body} = formatNotification(senderName, messageType, previewLevel);

    const tokens = Object.values(fcmTokens);
    const invalidTokens: string[] = [];

    for (const token of tokens) {
      try {
        await messaging.send({
          token,
          notification: {title, body},
          data: {
            conversationId,
            senderId,
            type: messageType,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "messages",
              priority: "high",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        });
      } catch (error: unknown) {
        const errorCode = (error as {code?: string})?.code;
        if (
          errorCode === "messaging/invalid-registration-token" ||
          errorCode === "messaging/registration-token-not-registered"
        ) {
          const deviceId = Object.keys(fcmTokens).find((k) => fcmTokens[k] === token);
          if (deviceId) invalidTokens.push(deviceId);
        }
      }
    }

    if (invalidTokens.length > 0) {
      const updates: Record<string, unknown> = {};
      for (const deviceId of invalidTokens) {
        updates[`fcmTokens.${deviceId}`] = null;
      }
      await db.collection("users").doc(recipientId).update(updates);
    }
  } catch (error) {
    logger.error("Notification send failed");
  }
}

function formatNotification(
  senderName: string,
  messageType: string,
  previewLevel: PreviewLevel
): {title: string; body: string} {
  if (previewLevel === "hidden") {
    return {
      title: "New Message",
      body: "You have a new message",
    };
  }

  const typeLabel = messageType === "media" ? "media" : "message";

  return {
    title: "New Message",
    body: `${senderName} sent you a ${typeLabel}`,
  };
}
