import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation.js";
import {hashBackupCode} from "../utils/hashing.js";
import {generateBackupCodes} from "../utils/random.js";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit.js";
import {TOTP_CONFIG} from "../config/constants.js";
import {db} from "../firebase.js";

export const enable2FA = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const ip = request.rawRequest.ip || "unknown";

    logger.info("2FA setup initiated");

    await checkIpRateLimit(db, ip, userId);
    await checkUserRateLimit(db, userId, "TOTP");

    try {
      const secret = speakeasy.generateSecret({
        name: `EchoProtocol (${request.auth?.token.email || userId})`,
        issuer: TOTP_CONFIG.issuer,
        length: TOTP_CONFIG.secretLength,
      });

      if (!secret.base32) {
        throw new HttpsError("internal", "Failed to generate 2FA secret");
      }

      const backupCodes = generateBackupCodes();
      const hashedBackupCodes = backupCodes.map((code) =>
        hashBackupCode(code)
      );

      await db.collection("2fa_secrets").doc(userId).set({
        secret: secret.base32,
        createdAt: FieldValue.serverTimestamp(),
        pendingBackupCodes: hashedBackupCodes,
      });

      await db.collection("users").doc(userId).update({
        twoFactorPending: true,
        twoFactorPendingAt: FieldValue.serverTimestamp(),
      });

      await db.collection("security_logs").add({
        userId,
        event: "2fa_enabled",
        timestamp: FieldValue.serverTimestamp(),
        ip: ip,
      });

      logger.info("2FA setup complete");

      return {
        success: true,
        qrCodeUrl: secret.otpauth_url,
        secret: secret.base32,
        backupCodes: backupCodes,
      };
    } catch (error) {
      logger.error("2FA setup failed");
      throw new HttpsError("internal", "Failed to enable 2FA");
    }
  }
);
