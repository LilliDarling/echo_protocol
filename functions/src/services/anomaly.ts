import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Alert on suspicious activity for security monitoring
 */
export async function alertSuspiciousActivity(
  db: admin.firestore.Firestore,
  ip: string,
  alertType: string,
  description: string
): Promise<void> {
  try {
    await db.collection("security_alerts").add({
      ip,
      alertType,
      description,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      severity: "high",
      resolved: false,
    });

    logger.warn("Security alert triggered", {ip, alertType, description});
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error("Failed to create security alert", {errorMessage});
  }
}
