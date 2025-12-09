import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {HttpsError} from "firebase-functions/v2/https";
import {RATE_LIMITS, ANOMALY_THRESHOLDS} from "../config/constants";
import {alertSuspiciousActivity} from "./anomaly";

/**
 * Check and enforce user-based rate limiting
 * @param {admin.firestore.Firestore} db - Firestore database instance
 * @param {string} userId - User ID to check rate limit for
 * @param {"TOTP" | "BACKUP_CODE"} limitType - Type of rate limit to check
 * @return {Promise<void>}
 */
export async function checkUserRateLimit(
  db: admin.firestore.Firestore,
  userId: string,
  limitType: "TOTP" | "BACKUP_CODE"
): Promise<void> {
  const config = RATE_LIMITS[limitType];
  const attemptsRef = db.collection("2fa_rate_limits").doc(userId);

  try {
    await db.runTransaction(async (transaction) => {
      const attemptsDoc = await transaction.get(attemptsRef);
      const now = admin.firestore.Timestamp.now();
      const windowStart = new Date(
        now.toMillis() - config.windowMinutes * 60 * 1000
      );

      let attempts: admin.firestore.Timestamp[] = [];
      if (attemptsDoc.exists) {
        const data = attemptsDoc.data();
        const key = limitType.toLowerCase();
        attempts = (data?.[key] || []) as admin.firestore.Timestamp[];
        attempts = attempts.filter(
          (timestamp: admin.firestore.Timestamp) =>
            timestamp.toDate() > windowStart
        );
      }

      if (attempts.length >= config.maxAttempts) {
        logger.warn("User rate limit exceeded", {
          userId,
          limitType,
          attempts: attempts.length,
        });
        throw new HttpsError(
          "resource-exhausted",
          `Too many ${limitType.toLowerCase()} verification attempts. ` +
          `Please try again in ${config.windowMinutes} minutes.`
        );
      }

      attempts.push(now);
      transaction.set(
        attemptsRef,
        {[limitType.toLowerCase()]: attempts, lastAttempt: now, userId: userId},
        {merge: true}
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error("Rate limit check failed", {userId, errorMessage});
    throw new HttpsError("internal", "Rate limit check failed");
  }
}

/**
 * Check and enforce IP-based rate limiting (prevents distributed attacks)
 * @param {admin.firestore.Firestore} db - Firestore database instance
 * @param {string} ip - IP address to check rate limit for
 * @param {string} userId - User ID making the request
 * @return {Promise<void>}
 */
export async function checkIpRateLimit(
  db: admin.firestore.Firestore,
  ip: string,
  userId: string
): Promise<void> {
  const ipRef = db.collection("ip_rate_limits").doc(ip);
  const config = RATE_LIMITS.IP;

  try {
    await db.runTransaction(async (transaction) => {
      const ipDoc = await transaction.get(ipRef);
      const now = admin.firestore.Timestamp.now();
      const windowStart = new Date(
        now.toMillis() - config.windowMinutes * 60 * 1000
      );

      type AttemptRecord = {
        timestamp: admin.firestore.Timestamp;
        userId: string;
      };
      let attempts: AttemptRecord[] = [];
      const uniqueUsers = new Set<string>();

      if (ipDoc.exists) {
        const data = ipDoc.data();
        attempts = (data?.attempts || []);

        attempts = attempts.filter(
          (attempt) => attempt.timestamp.toDate() > windowStart
        );

        attempts.forEach((attempt) => uniqueUsers.add(attempt.userId));
      }

      if (attempts.length >= config.maxAttemptsPerIp) {
        logger.warn("IP rate limit exceeded", {
          ip,
          attempts: attempts.length,
          uniqueUsers: uniqueUsers.size,
        });

        if (uniqueUsers.size >= ANOMALY_THRESHOLDS.multipleAccountAttacks) {
          await alertSuspiciousActivity(
            db,
            ip,
            "distributed_attack",
            `IP ${ip} attempted 2FA on ${uniqueUsers.size} different accounts`
          );
        }

        throw new HttpsError(
          "resource-exhausted",
          "Too many authentication attempts from this network. " +
          "Please try again later."
        );
      }

      attempts.push({timestamp: now, userId: userId});

      transaction.set(
        ipRef,
        {
          attempts: attempts,
          lastAttempt: now,
          uniqueUsers: Array.from(uniqueUsers),
        },
        {merge: true}
      );

      if (attempts.length >= ANOMALY_THRESHOLDS.suspiciousIpAttempts) {
        const msg = `IP ${ip} has made ${attempts.length} 2FA attempts ` +
          `in ${config.windowMinutes} minutes`;
        await alertSuspiciousActivity(db, ip, "high_attempt_rate", msg);
      }
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error("IP rate limit check failed", {ip, errorMessage});
    throw new HttpsError("internal", "Rate limit check failed");
  }
}
