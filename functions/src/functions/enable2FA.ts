import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation";
import {hashBackupCode} from "../utils/hashing";
import {generateBackupCodes} from "../utils/random";
import {TOTP_CONFIG} from "../config/constants";

const db = admin.firestore();

export const enable2FA = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const ip = request.rawRequest.ip || "unknown";

    logger.info("Enabling 2FA", {userId, ip});

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
        hashBackupCode(code, userId)
      );

      await db.collection("2fa_secrets").doc(userId).set({
        secret: secret.base32,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        pendingBackupCodes: hashedBackupCodes,
      });

      await db.collection("users").doc(userId).update({
        twoFactorPending: true,
        twoFactorPendingAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await db.collection("security_logs").add({
        userId,
        event: "2fa_enabled",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ip: ip,
      });

      logger.info("2FA enabled successfully", {userId, ip});

      return {
        success: true,
        qrCodeUrl: secret.otpauth_url,
        secret: secret.base32,
        backupCodes: backupCodes,
      };
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error("Failed to enable 2FA", {userId, errorMessage});
      throw new HttpsError("internal", "Failed to enable 2FA");
    }
  }
);
