import {randomBytes, pbkdf2Sync} from "crypto";
import {BACKUP_CODE_CONFIG} from "../config/constants.js";

/**
 * Hash a backup code using PBKDF2 with a random salt.
 * @param {string} code - The plaintext backup code to hash
 * @return {string} The salted hash in format "salt:hash"
 */
export function hashBackupCode(code: string): string {
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

/**
 * Verify a backup code against its stored hash.
 * @param {string} code - The plaintext backup code to verify
 * @param {string} storedHash - The stored hash in format "salt:hash"
 * @return {boolean} True if the code matches the hash
 */
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
