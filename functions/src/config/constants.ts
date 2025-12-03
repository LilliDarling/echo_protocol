/**
 * Configuration constants for 2FA and rate limiting
 */

export const RATE_LIMITS = {
  TOTP: {maxAttempts: 5, windowMinutes: 5},
  BACKUP_CODE: {maxAttempts: 3, windowMinutes: 5},
  IP: {maxAttemptsPerIp: 50, windowMinutes: 60},
  MESSAGE: {
    maxPerMinute: 30,
    maxPerHour: 500,
    conversationMaxPerMinute: 20,
    conversationMaxPerHour: 300,
  },
};

export const ANOMALY_THRESHOLDS = {
  suspiciousIpAttempts: 30,
  multipleAccountAttacks: 10,
  rapidFailures: 5,
};

export const TOTP_CONFIG = {
  secretLength: 32, // 256-bit
  window: 1, // Clock skew tolerance
  issuer: "EchoProtocol",
};

export const BACKUP_CODE_CONFIG = {
  count: 10,
  pbkdf2Iterations: 100000,
};

export const REPLAY_PROTECTION = {
  nonceExpiryHours: 1,
  clockSkewToleranceMinutes: 2,
};
