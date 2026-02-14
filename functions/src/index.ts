/**
 * Echo Protocol Cloud Functions - 2FA Server-Side Implementation
 */

import {setGlobalOptions} from "firebase-functions";
import "./firebase.js"; // Initialize Firebase first

setGlobalOptions({
  maxInstances: 10,
  memory: "256MiB",
  timeoutSeconds: 10,
});

export {verify2FATOTP} from "./functions/verify2FATOTP.js";
export {verify2FABackupCode} from "./functions/verify2FABackupCode.js";
export {enable2FA} from "./functions/enable2FA.js";
export {disable2FA} from "./functions/disable2FA.js";
export {regenerateBackupCodes} from "./functions/regenerateBackupCodes.js";
export {deliverMessage} from "./functions/deliverMessage.js";
export {acceptPartnerInvite} from "./functions/acceptPartnerInvite.js";
export {getPreKeyBundle} from "./functions/getPreKeyBundle.js";
export {uploadPreKeys} from "./functions/uploadPreKeys.js";
export {checkPreKeyCount} from "./functions/checkPreKeyCount.js";
export {cleanupExpiredMedia} from "./functions/cleanupExpiredMedia.js";
