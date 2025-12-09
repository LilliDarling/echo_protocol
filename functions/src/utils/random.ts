import {randomBytes} from "crypto";
import {BACKUP_CODE_CONFIG} from "../config/constants";

/**
 * Generate cryptographically secure backup codes
 * @param {number} count - Number of backup codes to generate
 * @return {string[]} Array of backup codes in format XXXX-XXXX
 */
export function generateBackupCodes(
  count: number = BACKUP_CODE_CONFIG.count
): string[] {
  const codes: string[] = [];

  for (let i = 0; i < count; i++) {
    const randomNumber = randomBytes(4).readUInt32BE(0);
    const part1 = (randomNumber % 10000).toString().padStart(4, "0");

    const randomNumber2 = randomBytes(4).readUInt32BE(0);
    const part2 = (randomNumber2 % 10000).toString().padStart(4, "0");

    codes.push(`${part1}-${part2}`);
  }

  return codes;
}
