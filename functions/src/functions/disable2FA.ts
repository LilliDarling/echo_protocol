import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation.js";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit.js";
import {TOTP_CONFIG} from "../config/constants.js";
import {db} from "../firebase.js";

export const disable2FA = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const {code} = request.data;
    const ip = request.rawRequest.ip || "unknown";

    if (!code) {
      throw new HttpsError(
        "invalid-argument",
        "TOTP code required to disable 2FA"
      );
    }

    logger.info("2FA disable initiated");

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
        throw new HttpsError(
          "permission-denied",
          "Invalid code. Cannot disable 2FA."
        );
      }

      await db.collection("2fa_secrets").doc(userId).delete();

      await db.collection("users").doc(userId).update({
        twoFactorEnabled: false,
        backupCodes: [],
        twoFactorDisabledAt: FieldValue.serverTimestamp(),
      });

      await db.collection("2fa_rate_limits").doc(userId).delete();

      await db.collection("security_logs").add({
        userId,
        event: "2fa_disabled",
        timestamp: FieldValue.serverTimestamp(),
        ip: ip,
      });

      logger.info("2FA disabled");

      return {
        success: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("2FA disable failed");
      throw new HttpsError("internal", "Failed to disable 2FA");
    }
  }
);
