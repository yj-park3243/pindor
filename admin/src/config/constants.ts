import type { Tier, SportType } from '@/types/user';

// 티어 설정 (7단계 퍼센타일 기반)
export const TIER_CONFIG: Record<Tier, { label: string; color: string; icon: string; percentile: string }> = {
  GRANDMASTER: {
    label: '그랜드마스터',
    color: '#FF4500',
    icon: '👑',
    percentile: '상위 1%',
  },
  MASTER: {
    label: '마스터',
    color: '#9B59B6',
    icon: '💎',
    percentile: '상위 3%',
  },
  PLATINUM: {
    label: '플래티넘',
    color: '#E5E4E2',
    icon: '⭐',
    percentile: '상위 10%',
  },
  GOLD: {
    label: '골드',
    color: '#FFD700',
    icon: '🛡️',
    percentile: '상위 30%',
  },
  SILVER: {
    label: '실버',
    color: '#C0C0C0',
    icon: '🛡️',
    percentile: '상위 60%',
  },
  BRONZE: {
    label: '브론즈',
    color: '#CD7F32',
    icon: '🛡️',
    percentile: '상위 80%',
  },
  IRON: {
    label: '아이언',
    color: '#71797E',
    icon: '⚫',
    percentile: '상위 100%',
  },
};

// 스포츠 타입 설정
export const SPORT_TYPE_CONFIG: Record<SportType, { label: string; icon: string }> = {
  GOLF: { label: '골프', icon: '⛳' },
  BILLIARDS: { label: '당구', icon: '🎱' },
  TENNIS: { label: '테니스', icon: '🎾' },
  TABLE_TENNIS: { label: '탁구', icon: '🏓' },
};

// 사용자 상태
export const USER_STATUS_CONFIG = {
  ACTIVE: { label: '활성', color: 'green' },
  SUSPENDED: { label: '정지', color: 'orange' },
  WITHDRAWN: { label: '탈퇴', color: 'red' },
} as const;

// 매칭 상태
export const MATCH_STATUS_CONFIG = {
  CHAT: { label: '채팅중', color: 'blue' },
  CONFIRMED: { label: '확정', color: 'green' },
  COMPLETED: { label: '완료', color: 'default' },
  CANCELLED: { label: '취소', color: 'red' },
  DISPUTED: { label: '이의신청', color: 'orange' },
} as const;

// 경기 결과 상태
export const GAME_RESULT_STATUS_CONFIG = {
  PENDING: { label: '대기중', color: 'default' },
  PROOF_UPLOADED: { label: '증빙업로드', color: 'blue' },
  VERIFIED: { label: '인증완료', color: 'green' },
  DISPUTED: { label: '이의신청', color: 'orange' },
  VOIDED: { label: '무효처리', color: 'red' },
} as const;

// 신고 상태
export const REPORT_STATUS_CONFIG = {
  PENDING: { label: '대기중', color: 'orange' },
  REVIEWED: { label: '검토중', color: 'blue' },
  RESOLVED: { label: '처리완료', color: 'green' },
  DISMISSED: { label: '기각', color: 'default' },
} as const;

// 신고 대상 타입
export const REPORT_TARGET_TYPE_CONFIG = {
  USER: { label: '사용자' },
  POST: { label: '게시글' },
  COMMENT: { label: '댓글' },
  GAME_RESULT: { label: '경기결과' },
  CHAT: { label: '채팅' },
} as const;

// 핀 레벨
export const PIN_LEVEL_CONFIG = {
  DONG: { label: '동', activationThreshold: 10 },
  GU: { label: '구/시', activationThreshold: 30 },
  CITY: { label: '도시', activationThreshold: 50 },
  PROVINCE: { label: '광역', activationThreshold: 100 },
} as const;

// 알림 대상 세그먼트
export const NOTIFICATION_SEGMENT_CONFIG = {
  ALL: { label: '전체 사용자' },
  ACTIVE_USERS: { label: '활성 사용자 (최근 30일)' },
  SPORT_GOLF: { label: '골프 사용자' },
  SPORT_BILLIARDS: { label: '당구 사용자' },
  SPORT_TENNIS: { label: '테니스 사용자' },
  SPORT_TABLE_TENNIS: { label: '탁구 사용자' },
  TIER_IRON: { label: '아이언 티어' },
  TIER_BRONZE: { label: '브론즈 티어' },
  TIER_SILVER: { label: '실버 티어' },
  TIER_GOLD: { label: '골드 티어' },
  TIER_PLATINUM: { label: '플래티넘 티어' },
  TIER_MASTER: { label: '마스터 티어' },
  TIER_GRANDMASTER: { label: '그랜드마스터 티어' },
} as const;

// 어드민 역할
export const ADMIN_ROLE_CONFIG = {
  SUPER_ADMIN: { label: '슈퍼 어드민', color: 'red' },
  ADMIN: { label: '어드민', color: 'orange' },
  MODERATOR: { label: '모더레이터', color: 'blue' },
} as const;

// K 계수 기본값
export const DEFAULT_K_FACTOR = {
  BEGINNER: 40,   // 첫 10게임
  INTERMEDIATE: 30, // 11~30게임
  STANDARD: 20,   // 31게임 이상
  PLATINUM: 16,   // 플래티넘 이상 티어
};

// 티어 점수 기준 (폴백용 — 유저 수 30명 미만 시 사용)
export const TIER_SCORE_THRESHOLDS = {
  IRON_MIN: 100,
  BRONZE_MIN: 900,
  SILVER_MIN: 1100,
  GOLD_MIN: 1300,
  PLATINUM_MIN: 1500,
  MASTER_MIN: 1650,
  GRANDMASTER_MIN: 1800,
};
