export interface SendMessageRequest {
  messageId: string;
  conversationId: string;
  recipientId: string;
  content: string;
  sequenceNumber: number;
  timestamp: number;
  senderKeyVersion: number;
  recipientKeyVersion: number;
  type?: string;
  metadata?: Record<string, unknown>;
  mediaType?: string;
  mediaUrl?: string;
  thumbnailUrl?: string;
}

export interface SendMessageResponse {
  success: boolean;
  messageId?: string;
  error?: string;
  retryAfterMs?: number;
  remainingMinute?: number;
  remainingHour?: number;
}

export interface ValidateMessageRequest {
  messageId: string;
  conversationId: string;
  recipientId: string;
  sequenceNumber: number;
  timestamp: number;
}

export interface ValidateMessageResponse {
  valid: boolean;
  token?: string;
  error?: string;
  retryAfterMs?: number;
  remainingMinute?: number;
  remainingHour?: number;
}
