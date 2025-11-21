import {createHash, pbkdf2Sync} from "crypto";
import {BACKUP_CODE_CONFIG} from "../config/constants";

/**
 * Hash backup code with PBKDF2 (prevents rainbow table attacks)
 */
export function hashBackupCode(code: string, userId: string): string {
  const salt = createHash("sha256").update(userId).digest("hex");
  const hash = pbkdf2Sync(
    code,
    salt,
    BACKUP_CODE_CONFIG.pbkdf2Iterations,
    64,
    "sha512"
  );
  return hash.toString("hex");
}
