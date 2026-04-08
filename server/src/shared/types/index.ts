// ─────────────────────────────────────
// 공통 응답 타입
// ─────────────────────────────────────

export interface ApiResponse<T = unknown> {
  success: true;
  data: T;
  meta?: PaginationMeta;
}

export interface ApiErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

export interface PaginationMeta {
  cursor?: string | null;
  hasMore: boolean;
  total?: number;
}

// ─────────────────────────────────────
// 커서 기반 페이지네이션
// ─────────────────────────────────────

export interface CursorPaginationQuery {
  cursor?: string;
  limit?: number;
}

export interface CursorPaginationResult<T> {
  items: T[];
  nextCursor: string | null;
  hasMore: boolean;
}

// ─────────────────────────────────────
// JWT Fastify 인증 확장
// ─────────────────────────────────────

declare module 'fastify' {
  interface FastifyRequest {
    user: {
      userId: string;
      email?: string | null;
    };
  }
}

// ─────────────────────────────────────
// GeoPoint
// ─────────────────────────────────────

export interface GeoPoint {
  lat: number;
  lng: number;
}

// ─────────────────────────────────────
// 알림 타입
// ─────────────────────────────────────

export type NotificationType =
  | 'MATCH_FOUND'
  | 'MATCH_REQUEST_RECEIVED'
  | 'MATCH_PENDING_ACCEPT'
  | 'MATCH_ACCEPTED'
  | 'MATCH_BOTH_ACCEPTED'
  | 'MATCH_REJECTED'
  | 'MATCH_EXPIRED'
  | 'MATCH_ACCEPT_TIMEOUT'
  | 'MATCH_WAITING_OPPONENT'
  | 'CHAT_MESSAGE'
  | 'CHAT_IMAGE'
  | 'GAME_RESULT_SUBMITTED'
  | 'GAME_RESULT_CONFIRMED'
  | 'SCORE_UPDATED'
  | 'TIER_CHANGED'
  | 'RESULT_DEADLINE'
  | 'COMMUNITY_REPLY'
  | 'MATCH_NO_SHOW_PENALTY'
  | 'MATCH_NO_SHOW_COMPENSATION'
  | 'MATCH_FORFEIT'
  | 'MATCH_FORFEIT_WIN';

export interface NotificationPayload {
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, string>;
  saveToDb?: boolean;
}

// ─────────────────────────────────────
// BullMQ Job 타입
// ─────────────────────────────────────

export interface PushJobData {
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface MatchExpiryJobData {
  matchRequestId: string;
}

export interface MatchAcceptTimeoutJobData {
  matchId: string;
  requesterUserId: string;
  opponentUserId: string;
  requesterRequestId: string;
  opponentRequestId: string;
}

export interface ResultDeadlineJobData {
  gameId: string;
  matchId: string;
}

export interface RankingRefreshJobData {
  pinId?: string;
  sportType?: string;
}

// ─────────────────────────────────────
// 팀 관련 타입
// ─────────────────────────────────────

export type TeamRoleType = 'CAPTAIN' | 'VICE_CAPTAIN' | 'MEMBER';
export type TeamStatusType = 'ACTIVE' | 'INACTIVE' | 'DISBANDED';
export type TeamMemberStatusType = 'ACTIVE' | 'INACTIVE' | 'BANNED';
export type TeamPostCategoryType = 'NOTICE' | 'SCHEDULE' | 'FREE';

export interface TeamSummary {
  id: string;
  name: string;
  slug: string;
  sportType: string;
  logoUrl: string | null;
  activityRegion: string | null;
  currentMembers: number;
  maxMembers: number;
  wins: number;
  losses: number;
  draws: number;
  teamScore: number;
  isRecruiting: boolean;
  status: TeamStatusType;
}

export interface TeamMemberSummary {
  id: string;
  userId: string;
  nickname: string;
  profileImageUrl: string | null;
  role: TeamRoleType;
  position: string | null;
  joinedAt: Date;
  status: TeamMemberStatusType;
}

export interface TeamNotificationType {
  type:
    | 'TEAM_MATCH_FOUND'
    | 'TEAM_MATCH_REQUEST_RECEIVED'
    | 'TEAM_MEMBER_JOINED'
    | 'TEAM_MEMBER_KICKED'
    | 'TEAM_RESULT_SUBMITTED'
    | 'TEAM_CHAT_MESSAGE';
}

// ─────────────────────────────────────
// NotificationService 인터페이스 (순환 의존 방지)
// ─────────────────────────────────────

export interface INotificationService {
  send(payload: NotificationPayload): Promise<void>;
  sendBulk(payloads: NotificationPayload[]): Promise<void>;
}
