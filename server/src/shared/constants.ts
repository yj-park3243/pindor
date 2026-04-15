// ─── 타이머/TTL ───
export const REFRESH_TOKEN_TTL = 30 * 24 * 3600; // 30일 (초)
export const KCP_KEY_TTL = 24 * 3600; // 24시간 (초)
export const RANKING_CACHE_TTL = 86400; // 24시간 (초)
export const RANKING_NATIONAL_TTL = 7 * 86400; // 7일 (초)

// ─── 매칭 ───
export const MATCH_ACCEPT_TIMEOUT_MINUTES = 10;
export const MATCH_EXPIRY_CHECK_INTERVAL = 5 * 60 * 1000; // 5분 (ms)
export const MATCHING_QUEUE_INTERVAL = 60_000; // 60초 fallback (ms)
export const MATCHING_QUEUE_MIN_INTERVAL = 2_000; // 최소 2초 (ms)
export const AUTO_RESOLVE_DELAY = 3 * 60 * 1000; // 3분 (ms)

// ─── 점수 ───
export const DEFAULT_SCORE = 1000;
export const MIN_SCORE = 100;
export const PLACEMENT_GAMES = 5;
export const CASUAL_K_FACTOR = 20;
export const NOSHOW_PENALTY_SCORE = -30;
export const NOSHOW_COMPENSATION_SCORE = 15;
export const REJECT_PENALTY_SCORE = -15;
export const REJECT_COMPENSATION_SCORE = 5;

// ─── 쿨다운 (분) ───
export const COOLDOWN_TIER1_MINUTES = 15; // 5회 이상 거절
export const COOLDOWN_TIER2_MINUTES = 30; // 10회 이상
export const COOLDOWN_TIER3_MINUTES = 60; // 20회 이상

// ─── 페이지네이션 ───
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 100;

// ─── 캐주얼 매칭 ───
export const CASUAL_MMR_RANGE = 600;

// ─── 기타 ───
export const MAX_RECENT_OPPONENTS = 5;
export const BCRYPT_SALT_ROUNDS = 12;
