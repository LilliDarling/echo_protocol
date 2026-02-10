export interface DeliverMessageRequest {
  messageId: string;
  recipientId: string;
  sealedEnvelope: {
    payload: string;
    ephemeralKey: string;
    timestamp: number;
    expireAt: number;
  };
  sequenceNumber: number;
}

export interface DeliverMessageResponse {
  success: boolean;
  messageId?: string;
  error?: string;
  retryAfterMs?: number;
}

export interface InboxMessage {
  sealedEnvelope: {
    payload: string;
    ephemeralKey: string;
    timestamp: number;
    expireAt: number;
  };
  deliveredAt: FirebaseFirestore.Timestamp;
  expireAt: FirebaseFirestore.Timestamp;
  isOutgoing: boolean;
}
