import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation.js";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit.js";
import {hashBackupCode} from "../utils/hashing.js";
import {generateBackupCodes} from "../utils/random.js";
import {TOTP_CONFIG} from "../config/constants.js";
import {db} from "../firebase.js";

export const regenerateBackupCodes = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const {code} = request.data;
    const ip = request.rawRequest.ip || "unknown";

    if (!code || typeof code !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "TOTP code required to regenerate backup codes"
      );
    }

    logger.info("Backup code regeneration initiated");

    await checkIpRateLimit(db, ip, userId);
    await checkUserRateLimit(db, userId, "TOTP");

    try {
      const secretDoc = await db
        .collection("2fa_secrets")
        .doc(userId)
        .get();

      if (!secretDoc.exists) {
        throw new HttpsError("not-found", "2FA not configured");
      }

      const secret = secretDoc.data()?.secret;
      const verified = speakeasy.totp.verify({
        secret: secret,
        encoding: "base32",
        token: code,
        window: TOTP_CONFIG.window,
      });

      if (!verified) {
        throw new HttpsError("permission-denied", "Invalid 2FA code");
      }

      const backupCodes = generateBackupCodes();
      const hashedBackupCodes = backupCodes.map((code) =>
        hashBackupCode(code)
      );

      await db.collection("users").doc(userId).update({
        backupCodes: hashedBackupCodes,
        backupCodesRegeneratedAt: FieldValue.serverTimestamp(),
      });

      await db.collection("security_logs").add({
        userId,
        event: "backup_codes_regenerated",
        timestamp: FieldValue.serverTimestamp(),
        ip: ip,
      });

      logger.info("Backup codes regenerated");

      return {
        success: true,
        backupCodes: backupCodes,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("Backup code regeneration failed");
      throw new HttpsError("internal", "Failed to regenerate backup codes");
    }
  }
);
