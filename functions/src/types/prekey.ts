export interface IdentityKeyData {
  ed25519: string;
  x25519: string;
  keyId: string;
}

export interface SignedPrekeyData {
  id: number;
  publicKey: string;
  signature: string;
  expiresAt: number;
}

export interface OneTimePrekeyData {
  id: number;
  publicKey: string;
}

export interface UploadPreKeysRequest {
  identityKey?: IdentityKeyData;
  signedPrekey?: SignedPrekeyData;
  oneTimePrekeys?: OneTimePrekeyData[];
}

export interface UploadPreKeysResponse {
  success: boolean;
  uploadedCount: number;
}

export interface GetPreKeyBundleRequest {
  recipientId: string;
}

export interface PreKeyBundleResponse {
  identityKey: IdentityKeyData;
  signedPrekey: SignedPrekeyData;
  oneTimePrekey?: OneTimePrekeyData;
  registrationId: number;
}

export interface CheckPreKeyCountResponse {
  oneTimePrekeyCount: number;
  signedPrekeyExpiresAt: number;
  needsReplenishment: boolean;
  replenishThreshold: number;
}
