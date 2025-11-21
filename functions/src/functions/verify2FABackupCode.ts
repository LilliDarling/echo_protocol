import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {validateRequest} from "../utils/validation";
import {hashBackupCode} from "../utils/hashing";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit";

const db = admin.firestore();

export const verify2FABackupCode = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth!.uid;
    const {code} = request.data;
    const ip = request.rawRequest.ip || "unknown";

    if (!code || typeof code !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Backup code is required and must be a string"
      );
    }

    logger.info("2FA backup code verification attempt", {userId, ip});

    await checkIpRateLimit(db, ip, userId);
    await checkUserRateLimit(db, userId, "BACKUP_CODE");

    try {
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();

      if (!userData?.twoFactorEnabled) {
        throw new HttpsError(
          "failed-precondition",
          "2FA is not enabled for this account"
        );
      }

      const hashedBackupCodes = userData.backupCodes || [];

      if (hashedBackupCodes.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "No backup codes available. Please regenerate backup codes."
        );
      }

      const hashedCode = hashBackupCode(code, userId);
      const codeIndex = hashedBackupCodes.indexOf(hashedCode);

      if (codeIndex === -1) {
        await db.collection("security_logs").add({
          userId,
          event: "2fa_backup_code_failed",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          ip: ip,
          userAgent: request.rawRequest.headers["user-agent"],
        });

        logger.warn("Invalid backup code", {userId, ip});

        throw new HttpsError(
          "permission-denied",
          "Invalid backup code"
        );
      }

      hashedBackupCodes.splice(codeIndex, 1);

      await db.collection("users").doc(userId).update({
        backupCodes: hashedBackupCodes,
      });

      await db.collection("security_logs").add({
        userId,
        event: "2fa_backup_code_success",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ip: ip,
        userAgent: request.rawRequest.headers["user-agent"],
        remainingBackupCodes: hashedBackupCodes.length,
      });

      logger.info("2FA backup code verification successful", {
        userId,
        ip,
        remainingCodes: hashedBackupCodes.length,
      });

      return {
        success: true,
        verified: true,
        remainingBackupCodes: hashedBackupCodes.length,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error("2FA backup code verification error", {userId, errorMessage});
      throw new HttpsError("internal", "Verification failed");
    }
  }
);
