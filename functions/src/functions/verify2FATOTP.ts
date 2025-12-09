import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit";

const db = admin.firestore();

export const verify2FATOTP = onCall(
  {maxInstances: 5},
  async (request) => {
    validateRequest(request);

    const userId = request.auth?.uid as string;
    const {code} = request.data;
    const ip = request.rawRequest.ip || "unknown";

    if (!code || typeof code !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "TOTP code is required and must be a string"
      );
    }

    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError(
        "invalid-argument",
        "TOTP code must be a 6-digit number"
      );
    }

    logger.info("2FA TOTP verification attempt", {userId, ip});

    await checkIpRateLimit(db, ip, userId);
    await checkUserRateLimit(db, userId, "TOTP");

    try {
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();

      if (!userData?.twoFactorEnabled) {
        throw new HttpsError(
          "failed-precondition",
          "2FA is not enabled for this account"
        );
      }

      const secretDoc = await db
        .collection("2fa_secrets")
        .doc(userId)
        .get();

      if (!secretDoc.exists) {
        logger.error("2FA secret not found", {userId});
        throw new HttpsError(
          "not-found",
          "2FA secret not found. Please re-enable 2FA."
        );
      }

      const secret = secretDoc.data()?.secret;

      if (!secret) {
        logger.error("2FA secret is empty", {userId});
        throw new HttpsError(
          "internal",
          "2FA configuration error"
        );
      }

      const verified = speakeasy.totp.verify({
        secret: secret,
        encoding: "base32",
        token: code,
        window: 1,
      });

      if (!verified) {
        await db.collection("security_logs").add({
          userId,
          event: "2fa_totp_failed",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          ip: ip,
          userAgent: request.rawRequest.headers["user-agent"],
        });

        logger.warn("Invalid TOTP code", {userId, ip});

        throw new HttpsError(
          "permission-denied",
          "Invalid 2FA code"
        );
      }

      await db.collection("security_logs").add({
        userId,
        event: "2fa_totp_success",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ip: ip,
        userAgent: request.rawRequest.headers["user-agent"],
      });

      logger.info("2FA TOTP verification successful", {userId, ip});

      return {
        success: true,
        verified: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error("2FA TOTP verification error", {userId, errorMessage});
      throw new HttpsError("internal", "Verification failed");
    }
  }
);
