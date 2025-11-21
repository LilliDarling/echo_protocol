import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation";
import {hashBackupCode} from "../utils/hashing";
import {generateBackupCodes} from "../utils/random";
import {TOTP_CONFIG} from "../config/constants";

const db = admin.firestore();

export const regenerateBackupCodes = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth!.uid;
    const {code} = request.data;
    const ip = request.rawRequest.ip || "unknown";

    if (!code || typeof code !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "TOTP code required to regenerate backup codes"
      );
    }

    logger.info("Regenerating backup codes", {userId, ip});

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
        hashBackupCode(code, userId)
      );

      await db.collection("users").doc(userId).update({
        backupCodes: hashedBackupCodes,
        backupCodesRegeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await db.collection("security_logs").add({
        userId,
        event: "backup_codes_regenerated",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ip: ip,
      });

      logger.info("Backup codes regenerated successfully", {userId, ip});

      return {
        success: true,
        backupCodes: backupCodes,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error("Failed to regenerate backup codes", {userId, errorMessage});
      throw new HttpsError("internal", "Failed to regenerate backup codes");
    }
  }
);
