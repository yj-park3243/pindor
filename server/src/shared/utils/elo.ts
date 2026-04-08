import { Tier } from '../../entities/index.js';

// ─────────────────────────────────────
// ELO 계산 함수 (PRD 섹션 5)
// ─────────────────────────────────────

// ─────────────────────────────────────
// 티어 프로그레스 정보
// ─────────────────────────────────────

export interface TierInfo {
  tier: string;              // IRON, BRONZE, SILVER, GOLD, PLATINUM, MASTER, GRANDMASTER
  subTier: 1 | 2 | 3;       // I=1, II=2, III=3
  rangeMin: number;
  rangeMax: number;
  nextThreshold: number | null; // null for GRANDMASTER III
  pointsToNext: number | null;
  progress: number;          // 0.0 ~ 1.0
}

/**
 * 점수 기반 티어 프로그레스 정보 계산
 *
 * 티어 범위:
 * IRON:        0-899   (I:0-299,    II:300-599,   III:600-899)
 * BRONZE:      900-1099 (I:900-959,  II:960-1029,  III:1030-1099)
 * SILVER:      1100-1299 (I:1100-1159, II:1160-1229, III:1230-1299)
 * GOLD:        1300-1499 (I:1300-1359, II:1360-1429, III:1430-1499)
 * PLATINUM:    1500-1649 (I:1500-1549, II:1550-1599, III:1600-1649)
 * MASTER:      1650-1799 (I:1650-1699, II:1700-1749, III:1750-1799)
 * GRANDMASTER: 1800+    (I:1800-1849, II:1850-1899, III:1900+)
 */
export function getTierInfo(score: number): TierInfo {
  // 서브 티어 경계 정의: [rangeMin, rangeMax, nextThreshold | null]
  const subTiers: Array<{
    tier: string;
    subTier: 1 | 2 | 3;
    rangeMin: number;
    rangeMax: number;
    nextThreshold: number | null;
  }> = [
    // IRON
    { tier: 'IRON', subTier: 1, rangeMin: 0, rangeMax: 299, nextThreshold: 300 },
    { tier: 'IRON', subTier: 2, rangeMin: 300, rangeMax: 599, nextThreshold: 600 },
    { tier: 'IRON', subTier: 3, rangeMin: 600, rangeMax: 899, nextThreshold: 900 },
    // BRONZE
    { tier: 'BRONZE', subTier: 1, rangeMin: 900, rangeMax: 959, nextThreshold: 960 },
    { tier: 'BRONZE', subTier: 2, rangeMin: 960, rangeMax: 1029, nextThreshold: 1030 },
    { tier: 'BRONZE', subTier: 3, rangeMin: 1030, rangeMax: 1099, nextThreshold: 1100 },
    // SILVER
    { tier: 'SILVER', subTier: 1, rangeMin: 1100, rangeMax: 1159, nextThreshold: 1160 },
    { tier: 'SILVER', subTier: 2, rangeMin: 1160, rangeMax: 1229, nextThreshold: 1230 },
    { tier: 'SILVER', subTier: 3, rangeMin: 1230, rangeMax: 1299, nextThreshold: 1300 },
    // GOLD
    { tier: 'GOLD', subTier: 1, rangeMin: 1300, rangeMax: 1359, nextThreshold: 1360 },
    { tier: 'GOLD', subTier: 2, rangeMin: 1360, rangeMax: 1429, nextThreshold: 1430 },
    { tier: 'GOLD', subTier: 3, rangeMin: 1430, rangeMax: 1499, nextThreshold: 1500 },
    // PLATINUM
    { tier: 'PLATINUM', subTier: 1, rangeMin: 1500, rangeMax: 1549, nextThreshold: 1550 },
    { tier: 'PLATINUM', subTier: 2, rangeMin: 1550, rangeMax: 1599, nextThreshold: 1600 },
    { tier: 'PLATINUM', subTier: 3, rangeMin: 1600, rangeMax: 1649, nextThreshold: 1650 },
    // MASTER
    { tier: 'MASTER', subTier: 1, rangeMin: 1650, rangeMax: 1699, nextThreshold: 1700 },
    { tier: 'MASTER', subTier: 2, rangeMin: 1700, rangeMax: 1749, nextThreshold: 1750 },
    { tier: 'MASTER', subTier: 3, rangeMin: 1750, rangeMax: 1799, nextThreshold: 1800 },
    // GRANDMASTER
    { tier: 'GRANDMASTER', subTier: 1, rangeMin: 1800, rangeMax: 1849, nextThreshold: 1850 },
    { tier: 'GRANDMASTER', subTier: 2, rangeMin: 1850, rangeMax: 1899, nextThreshold: 1900 },
    { tier: 'GRANDMASTER', subTier: 3, rangeMin: 1900, rangeMax: Infinity, nextThreshold: null },
  ];

  // 점수에 해당하는 서브 티어 찾기
  const clampedScore = Math.max(0, score);
  const found = subTiers.find(
    (st) => clampedScore >= st.rangeMin && clampedScore <= st.rangeMax,
  ) ?? subTiers[subTiers.length - 1]; // 최대 범위 초과 시 GRANDMASTER III

  const rangeMin = found.rangeMin;
  const rangeMax = found.nextThreshold !== null ? found.nextThreshold - 1 : found.rangeMin + 99;
  const rangeSize = rangeMax - rangeMin + 1;

  let progress: number;
  let pointsToNext: number | null;

  if (found.nextThreshold === null) {
    // GRANDMASTER III: 1900점부터 100점 단위로 progress 표시 (1.0 상한 없음은 1.0으로 cap)
    progress = Math.min(1.0, (clampedScore - found.rangeMin) / 100);
    pointsToNext = null;
  } else {
    progress = Math.min(1.0, (clampedScore - rangeMin) / rangeSize);
    pointsToNext = found.nextThreshold - clampedScore;
  }

  return {
    tier: found.tier,
    subTier: found.subTier,
    rangeMin,
    rangeMax: found.nextThreshold !== null ? rangeMax : found.rangeMin + 99,
    nextThreshold: found.nextThreshold,
    pointsToNext,
    progress: Math.max(0, progress),
  };
}

export type GameResult = 'WIN' | 'LOSS' | 'DRAW';

export interface EloCalculationInput {
  ratingA: number;
  ratingB: number;
  kFactor: number;
  result: GameResult;
}

export interface EloCalculationResult {
  newRatingA: number;
  change: number;
}

/**
 * ELO 점수 계산
 * E_A = 1 / (1 + 10^((R_B - R_A) / 400))
 * 새 점수 = R_A + K × (S_A - E_A)
 */
export function calculateElo(params: EloCalculationInput): EloCalculationResult {
  const { ratingA, ratingB, kFactor, result } = params;

  // 기댓값 계산
  const expectedA = 1 / (1 + Math.pow(10, (ratingB - ratingA) / 400));

  // 실제 결과 수치화
  const actualScore = result === 'WIN' ? 1 : result === 'DRAW' ? 0.5 : 0;

  // 점수 변동 (반올림)
  const change = Math.round(kFactor * (actualScore - expectedA));
  const newRatingA = Math.max(100, ratingA + change); // 최소 100점 보장

  return { newRatingA, change };
}

/**
 * K 계수 결정 (PRD 섹션 5.1)
 *
 * | 조건 | K 계수 |
 * |------|--------|
 * | 첫 10게임 | 40 |
 * | 11~30게임 | 30 |
 * | 31게임 이상 | 20 |
 * | 플래티넘 이상 티어 | 16 |
 */
export function getKFactor(gamesPlayed: number, tier: Tier): number {
  if (tier === Tier.PLATINUM || tier === Tier.DIAMOND) return 16;
  if (gamesPlayed <= 10) return 40;
  if (gamesPlayed <= 30) return 30;
  return 20;
}

/**
 * G핸디 → 초기 점수 변환
 * 변동폭을 작게 유지 (950~1050) — 배치 게임에서 실력 반영
 * 선형 매핑: G핸디 0 → 1050점, G핸디 54 → 950점
 */
export function gHandicapToInitialScore(gHandicap: number): number {
  const maxHandicap = 54;
  const minScore = 950;
  const maxScore = 1050;

  const clampedHandicap = Math.max(0, Math.min(maxHandicap, gHandicap));
  const score = maxScore - (clampedHandicap / maxHandicap) * (maxScore - minScore);

  return Math.round(score);
}

/**
 * 점수 → 티어 폴백 계산 (유저 수 < 30명일 때 사용)
 * 절대 점수 기준으로 티어 결정
 */
export function calculateTier(score: number): Tier {
  return calculateTierFallback(score);
}

/**
 * 절대 점수 기준 티어 계산 (폴백용, 유저 수 < 30명)
 */
export function calculateTierFallback(score: number): Tier {
  if (score >= 1800) return Tier.DIAMOND;
  if (score >= 1500) return Tier.PLATINUM;
  if (score >= 1300) return Tier.GOLD;
  if (score >= 1100) return Tier.SILVER;
  if (score >= 900) return Tier.BRONZE;
  return Tier.BRONZE;
}

/**
 * 퍼센타일 기반 티어 계산
 * 전체 유저의 점수 분포에서 상위 몇 %인지 계산하여 티어 결정
 *
 * @param userScore - 해당 유저의 점수
 * @param allScoresSorted - 내림차순 정렬된 전체 유저 점수 배열
 */
export function calculateTierByPercentile(
  userScore: number,
  allScoresSorted: number[], // 내림차순 정렬된 전체 점수 배열
): Tier {
  if (allScoresSorted.length === 0) return Tier.BRONZE;

  // 유저 점수보다 높은 점수가 몇 개인지 찾기 (내림차순이므로 처음으로 같거나 작은 인덱스)
  const rank = allScoresSorted.findIndex(s => userScore >= s);
  const effectiveRank = rank === -1 ? allScoresSorted.length : rank;
  const percentile = (effectiveRank / allScoresSorted.length) * 100;

  if (percentile <= 5) return Tier.DIAMOND;
  if (percentile <= 15) return Tier.PLATINUM;
  if (percentile <= 35) return Tier.GOLD;
  if (percentile <= 60) return Tier.SILVER;
  return Tier.BRONZE;
}

/**
 * 티어 강등 보호 적용 (PRD 섹션 5.3)
 * 티어 경계에서 최대 3게임 유예
 */
export function calculateTierWithBuffer(
  score: number,
  currentTier: Tier,
  gamesInCurrentTier: number,
): Tier {
  const rawTier = calculateTier(score);
  const tierOrder: Tier[] = [
    Tier.BRONZE,
    Tier.SILVER,
    Tier.GOLD,
    Tier.PLATINUM,
    Tier.DIAMOND,
  ];

  // 강등 가능 상황
  if (tierOrder.indexOf(rawTier) < tierOrder.indexOf(currentTier)) {
    if (gamesInCurrentTier < 3) {
      return currentTier; // 3게임 유예
    }
  }

  return rawTier;
}

/**
 * 골프 승자 결정 (핸디캡 적용 순 타수)
 * PRD 섹션 5.1 골프 특수 규칙
 */
export function determineGolfWinner(
  requesterStrokes: number,
  opponentStrokes: number,
  requesterHandicap: number,
  opponentHandicap: number,
): 'REQUESTER' | 'OPPONENT' | 'DRAW' {
  const requesterNet = requesterStrokes - requesterHandicap;
  const opponentNet = opponentStrokes - opponentHandicap;

  if (requesterNet < opponentNet) return 'REQUESTER';
  if (opponentNet < requesterNet) return 'OPPONENT';
  return 'DRAW';
}

/**
 * 양측 ELO 점수 업데이트 계산
 * A(승자) vs B(패자) 경우 양측 변동폭 반환
 */
export function calculateBothElo(
  scoreA: number,
  scoreB: number,
  kFactorA: number,
  kFactorB: number,
  resultForA: GameResult,
): {
  newScoreA: number;
  changeA: number;
  newScoreB: number;
  changeB: number;
} {
  const { newRatingA, change: changeA } = calculateElo({
    ratingA: scoreA,
    ratingB: scoreB,
    kFactor: kFactorA,
    result: resultForA,
  });

  const resultForB: GameResult =
    resultForA === 'WIN' ? 'LOSS' : resultForA === 'LOSS' ? 'WIN' : 'DRAW';

  const { newRatingA: newRatingB, change: changeB } = calculateElo({
    ratingA: scoreB,
    ratingB: scoreA,
    kFactor: kFactorB,
    result: resultForB,
  });

  return {
    newScoreA: newRatingA,
    changeA,
    newScoreB: newRatingB,
    changeB,
  };
}
