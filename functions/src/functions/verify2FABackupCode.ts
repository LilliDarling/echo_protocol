import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {validateRequest} from "../utils/validation.js";
import {verifyBackupCode} from "../utils/hashing.js";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit.js";
import {db, auth} from "../firebase.js";

export const verify2FABackupCode = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const {code} = request.data;
    const ip = request.rawRequest.ip || "unknown";

    if (!code || typeof code !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Backup code is required and must be a string"
      );
    }

    logger.info("Backup code verification attempt");

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

      const codeIndex = hashedBackupCodes.findIndex(
        (storedHash: string) => verifyBackupCode(code, storedHash)
      );

      if (codeIndex === -1) {
        await db.collection("security_logs").add({
          userId,
          event: "2fa_backup_code_failed",
          timestamp: FieldValue.serverTimestamp(),
          ip: ip,
          userAgent: request.rawRequest.headers["user-agent"],
        });

        logger.warn("Backup code verification failed");

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
        timestamp: FieldValue.serverTimestamp(),
        ip: ip,
        userAgent: request.rawRequest.headers["user-agent"],
        remainingBackupCodes: hashedBackupCodes.length,
      });

      let twoFactorVerifiedAt: number | null = null;
      try {
        twoFactorVerifiedAt = Date.now();
        const user = await auth.getUser(userId);
        const existingClaims = user.customClaims || {};
        await auth.setCustomUserClaims(userId, {
          ...existingClaims,
          twoFactorVerifiedAt,
        });
      } catch (claimsError) {
        logger.warn("Failed to set 2FA custom claims", {error: claimsError});
      }

      logger.info("Backup code verification successful");

      return {
        success: true,
        verified: true,
        remainingBackupCodes: hashedBackupCodes.length,
        twoFactorVerifiedAt,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("Backup code verification error");
      throw new HttpsError("internal", "Verification failed");
    }
  }
);
