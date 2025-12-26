import {randomBytes, pbkdf2Sync} from "crypto";
import {BACKUP_CODE_CONFIG} from "../config/constants";

export function hashBackupCode(code: string, _userId: string): string {
  const salt = randomBytes(32).toString("hex");
  const hash = pbkdf2Sync(
    code,
    salt,
    BACKUP_CODE_CONFIG.pbkdf2Iterations,
    64,
    "sha512"
  );
  return `${salt}:${hash.toString("hex")}`;
}

export function verifyBackupCode(code: string, storedHash: string): boolean {
  const parts = storedHash.split(":");
  if (parts.length !== 2) return false;
  const [salt, expectedHash] = parts;
  const hash = pbkdf2Sync(
    code,
    salt,
    BACKUP_CODE_CONFIG.pbkdf2Iterations,
    64,
    "sha512"
  );
  return hash.toString("hex") === expectedHash;
}
