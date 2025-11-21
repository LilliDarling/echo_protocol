import {HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * Validate request authentication and basic security checks
 */
export function validateRequest(request: any): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const userAgent = request.rawRequest.headers["user-agent"];
  if (!userAgent || userAgent.length < 10) {
    logger.warn("Suspicious request without proper user agent", {
      userId: request.auth.uid,
      userAgent,
    });
  }

  const ip = request.rawRequest.ip;
  if (!ip || ip === "0.0.0.0" || ip === "::") {
    throw new HttpsError("invalid-argument", "Invalid request source");
  }
}
