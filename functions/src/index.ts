/**
 * Echo Protocol Cloud Functions - 2FA Server-Side Implementation
 */

import {setGlobalOptions} from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

setGlobalOptions({
  maxInstances: 10,
  memory: "256MiB",
  timeoutSeconds: 10,
});

export {verify2FATOTP} from "./functions/verify2FATOTP";
export {verify2FABackupCode} from "./functions/verify2FABackupCode";
export {enable2FA} from "./functions/enable2FA";
export {disable2FA} from "./functions/disable2FA";
export {regenerateBackupCodes} from "./functions/regenerateBackupCodes";
export {validateMessageSend} from "./functions/validateMessageSend";
export {sendMessage} from "./functions/sendMessage";
export {acceptPartnerInvite} from "./functions/acceptPartnerInvite";
export {getPreKeyBundle} from "./functions/getPreKeyBundle";
export {uploadPreKeys} from "./functions/uploadPreKeys";
export {checkPreKeyCount} from "./functions/checkPreKeyCount";
