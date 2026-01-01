import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as speakeasy from "speakeasy";
import {validateRequest} from "../utils/validation.js";
import {checkUserRateLimit, checkIpRateLimit} from "../services/rateLimit.js";
import {db, auth} from "../firebase.js";

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

    logger.info("2FA verification attempt");

    await checkIpRateLimit(db, ip, userId);
    await checkUserRateLimit(db, userId, "TOTP");

    try {
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();

      const isPending = userData?.twoFactorPending === true;
      const isEnabled = userData?.twoFactorEnabled === true;

      if (!isPending && !isEnabled) {
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
        logger.error("2FA configuration error");
        throw new HttpsError(
          "not-found",
          "2FA secret not found. Please re-enable 2FA."
        );
      }

      const secretData = secretDoc.data();
      const secret = secretData?.secret;

      if (!secret) {
        logger.error("2FA configuration error");
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
          timestamp: FieldValue.serverTimestamp(),
          ip: ip,
          userAgent: request.rawRequest.headers["user-agent"],
        });

        logger.warn("2FA verification failed");

        throw new HttpsError(
          "permission-denied",
          "Invalid 2FA code"
        );
      }

      if (isPending) {
        const pendingBackupCodes = secretData?.pendingBackupCodes;
        await db.collection("users").doc(userId).update({
          twoFactorEnabled: true,
          twoFactorEnabledAt: FieldValue.serverTimestamp(),
          twoFactorPending: FieldValue.delete(),
          twoFactorPendingAt: FieldValue.delete(),
          backupCodes: pendingBackupCodes || [],
        });
        await db.collection("2fa_secrets").doc(userId).update({
          pendingBackupCodes: FieldValue.delete(),
        });
      }

      await db.collection("security_logs").add({
        userId,
        event: isPending ? "2fa_activated" : "2fa_totp_success",
        timestamp: FieldValue.serverTimestamp(),
        ip: ip,
        userAgent: request.rawRequest.headers["user-agent"],
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

      logger.info("2FA verification successful");

      return {
        success: true,
        verified: true,
        activated: isPending,
        twoFactorVerifiedAt,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("2FA verification error");
      throw new HttpsError("internal", "Verification failed");
    }
  }
);
