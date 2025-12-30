import {Firestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

/**
 * Alert on suspicious activity for security monitoring
 * @param {Firestore} db - Firestore database instance
 * @param {string} ip - IP address of the suspicious activity
 * @param {string} alertType - Type of alert (e.g., distributed_attack)
 * @param {string} description - Human-readable description of the alert
 * @return {Promise<void>}
 */
export async function alertSuspiciousActivity(
  db: Firestore,
  ip: string,
  alertType: string,
  description: string
): Promise<void> {
  try {
    await db.collection("security_alerts").add({
      ip,
      alertType,
      description,
      timestamp: FieldValue.serverTimestamp(),
      severity: "high",
      resolved: false,
    });

    logger.warn("Security alert triggered", {ip, alertType, description});
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error("Failed to create security alert", {errorMessage});
  }
}
