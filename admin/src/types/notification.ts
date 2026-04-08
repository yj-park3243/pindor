export type NotificationType =
  | 'MATCH_FOUND'
  | 'MATCH_REQUEST_RECEIVED'
  | 'MATCH_ACCEPTED'
  | 'MATCH_REJECTED'
  | 'MATCH_EXPIRED'
  | 'CHAT_MESSAGE'
  | 'CHAT_IMAGE'
  | 'GAME_RESULT_SUBMITTED'
  | 'GAME_RESULT_CONFIRMED'
  | 'SCORE_UPDATED'
  | 'TIER_CHANGED'
  | 'RESULT_DEADLINE'
  | 'COMMUNITY_REPLY'
  | 'ANNOUNCEMENT';

export type NotificationTargetSegment =
  | 'ALL'
  | 'ACTIVE_USERS'
  | 'SPORT_GOLF'
  | 'SPORT_BILLIARDS'
  | 'SPORT_TENNIS'
  | 'SPORT_TABLE_TENNIS'
  | 'TIER_BRONZE'
  | 'TIER_SILVER'
  | 'TIER_GOLD'
  | 'TIER_PLATINUM';

export interface Notification {
  id: string;
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data: Record<string, string>;
  isRead: boolean;
  createdAt: string;
}

export interface NotificationSendRequest {
  title: string;
  body: string;
  targetSegment: NotificationTargetSegment;
  data?: Record<string, string>;
}

export interface NotificationLog {
  id: string;
  title: string;
  body: string;
  targetSegment: NotificationTargetSegment;
  sentCount: number;
  sentBy: string;
  sentAt: string;
}
