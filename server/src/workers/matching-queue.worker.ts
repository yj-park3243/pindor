import 'reflect-metadata';
import 'dotenv/config';
import { AppDataSource } from '../config/database.js';
import { redis } from '../config/redis.js';
import {
  MatchRequest,
  Match,
  ChatRoom,
  MatchAcceptance,
  Message,
  UserBlock,
} from '../entities/index.js';
import { MatchRequestStatus, MessageType, RoomType } from '../entities/index.js';
import { In } from 'typeorm';
import { decayRD } from '../shared/utils/glicko2.js';
import { sendAdminAlert, escapeHtml } from '../shared/services/telegram.service.js';

// ─────────────────────────────────────
// 대기 중인 매칭 요청 타입 (Glicko-2 + 매너 필드 포함)
// ─────────────────────────────────────

interface WaitingRequest {
  id: string;
  requesterId: string;
  sportsProfileId: string;
  pinId: string;
  sportType: string;
  desiredDate: string | null;
  desiredTimeSlot: string | null;
  isCasual: boolean;
  createdAt: Date;
  expiresAt: Date;
  currentScore: number;
  glickoRating: number;
  glickoRd: number;
  glickoVolatility: number | null;
  glickoLastUpdatedAt: Date | null;
  isPlacement: boolean;
  lossStreak: number;
  recentOpponentIds: string[];
  winStreak: number;
  // 매너 점수 필드
  mannerTotal: number;
  mannerCount: number;
  // 성별/나이 필터 (matching.service.ts 즉시 매칭과 동일 정책)
  gender: string | null;
  birthDate: string | null;
  genderPreference: string | null;
  minAge: number | null;
  maxAge: number | null;
}

// ─────────────────────────────────────
// 매너 등급 시스템
// ─────────────────────────────────────

type MannerTier = 'GOOD' | 'NORMAL' | 'BAD';

const MANNER_MIN_SAMPLES = parseInt(process.env.MANNER_MIN_SAMPLES || '5', 10);
const MANNER_GOOD_THRESHOLD = parseFloat(process.env.MANNER_GOOD_THRESHOLD || '4.0');
const MANNER_BAD_THRESHOLD = parseFloat(process.env.MANNER_BAD_THRESHOLD || '2.5');

function getMannerTier(req: WaitingRequest): MannerTier {
  if ((req.mannerCount ?? 0) < MANNER_MIN_SAMPLES) return 'NORMAL';
  const avg = (req.mannerTotal ?? 0) / req.mannerCount;
  if (avg >= MANNER_GOOD_THRESHOLD) return 'GOOD';
  if (avg < MANNER_BAD_THRESHOLD) return 'BAD';
  return 'NORMAL';
}

function mannerCostAdjustment(a: WaitingRequest, b: WaitingRequest): number {
  const ta = getMannerTier(a);
  const tb = getMannerTier(b);
  const pair = [ta, tb].sort().join('-');
  // 정렬된 조합: 'BAD-BAD' | 'BAD-GOOD' | 'BAD-NORMAL' | 'GOOD-GOOD' | 'GOOD-NORMAL' | 'NORMAL-NORMAL'
  switch (pair) {
    case 'GOOD-GOOD':   return -50;
    case 'BAD-GOOD':    return +200;
    case 'BAD-NORMAL':  return +50;
    case 'BAD-BAD':     return -100;
    case 'GOOD-NORMAL':
    case 'NORMAL-NORMAL':
    default:            return 0;
  }
}

// ─────────────────────────────────────
// 대기 비율: 0.0 (방금 등록) ~ 1.0 (만료 직전)
// 최소 윈도우 30분 보장 (매우 짧은 expiresAt 방어)
// ─────────────────────────────────────

// MMR 범위 확장 테스트용: env로 최소 윈도우/팽창 가속 가능
// MATCH_WAIT_WINDOW_MIN: 분 단위 최소 윈도우 (기본 30분, 테스트 시 1~5 분으로 단축)
// MATCH_WAIT_RATIO_BOOST: waitRatio 배수 (기본 1.0, 테스트 시 5.0 등으로 가속)
const TEST_MIN_WINDOW_MS = (() => {
  const v = parseFloat(process.env.MATCH_WAIT_WINDOW_MIN || '30');
  return (Number.isFinite(v) && v > 0 ? v : 30) * 60 * 1000;
})();
const TEST_WAIT_RATIO_BOOST = (() => {
  const v = parseFloat(process.env.MATCH_WAIT_RATIO_BOOST || '1');
  return Number.isFinite(v) && v > 0 ? v : 1;
})();

function getWaitRatio(req: WaitingRequest): number {
  const now = Date.now();
  const created = new Date(req.createdAt).getTime();
  const expires = new Date(req.expiresAt).getTime();
  const totalWindow = Math.max(expires - created, TEST_MIN_WINDOW_MS);
  const raw = (now - created) / totalWindow;
  return Math.min(1.0, Math.max(0.0, raw * TEST_WAIT_RATIO_BOOST));
}

// ─────────────────────────────────────
// 팽창 계수: 초기 20% 보호 구간 + 이후 이차 곡선
// waitRatio 0.2 이하 → 0.0, 1.0 → 1.0
// ─────────────────────────────────────

function expansionFactor(waitRatio: number): number {
  if (waitRatio <= 0.2) return 0.0; // 보호 구간
  const adjusted = (waitRatio - 0.2) / 0.8;
  return adjusted * adjusted; // 이차 곡선
}

// ─────────────────────────────────────
// 유효 MMR 범위: 대기 시간 + RD 기반으로 동적 계산
// 하드캡 250 적용
// ─────────────────────────────────────

function getEffectiveRange(req: WaitingRequest): number {
  const BASE_RANGE = 50;
  const MAX_RANGE = 350;
  const waitRatio = getWaitRatio(req);
  const range = BASE_RANGE + (MAX_RANGE - BASE_RANGE) * expansionFactor(waitRatio);

  // RD 기반 멀티플라이어: 불확실성이 높을수록 범위 확장
  const rd = req.glickoRd || 350;
  const rdMultiplier = req.isPlacement
    ? Math.min(1.3, 1.0 + (rd - 50) / 350 * 0.3) // 배치 게임: 최대 1.3배
    : 1.0 + (rd - 50) / 350;

  return Math.min(range * rdMultiplier, 250); // 하드캡 250
}

// ─────────────────────────────────────
// 24시간 내 최근 상대 여부 확인
// ─────────────────────────────────────

function isRecentOpponent(a: WaitingRequest, b: WaitingRequest): boolean {
  return (a.recentOpponentIds || []).includes(b.sportsProfileId) ||
         (b.recentOpponentIds || []).includes(a.sportsProfileId);
}

function ageOf(birthDate: string | null): number | null {
  if (!birthDate) return null;
  const bd = new Date(birthDate);
  if (isNaN(bd.getTime())) return null;
  const now = new Date();
  let age = now.getFullYear() - bd.getFullYear();
  const m = now.getMonth() - bd.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < bd.getDate())) age--;
  return age;
}

// 즉시 매칭(matching.service.ts:655~680)과 동일 정책으로 성별 SAME / OPPOSITE / minAge / maxAge 검증
function isCompatibleGenderAge(a: WaitingRequest, b: WaitingRequest): boolean {
  // SAME 선호 — 양쪽 성별 정보가 있어야 하고 일치해야 함
  if (a.genderPreference === 'SAME') {
    if (!a.gender || !b.gender || a.gender !== b.gender) return false;
  }
  if (b.genderPreference === 'SAME') {
    if (!a.gender || !b.gender || a.gender !== b.gender) return false;
  }
  // OPPOSITE 선호 — 양쪽 성별 정보가 있어야 하고 서로 달라야 함
  if (a.genderPreference === 'OPPOSITE') {
    if (!a.gender || !b.gender || a.gender === b.gender) return false;
  }
  if (b.genderPreference === 'OPPOSITE') {
    if (!a.gender || !b.gender || a.gender === b.gender) return false;
  }
  const ageA = ageOf(a.birthDate);
  const ageB = ageOf(b.birthDate);
  // A가 요구한 minAge/maxAge는 B의 나이로 검증, B가 요구한 minAge/maxAge는 A의 나이로 검증
  if (a.minAge !== null && a.minAge !== undefined) {
    if (ageB === null || ageB < a.minAge) return false;
  }
  if (a.maxAge !== null && a.maxAge !== undefined) {
    if (ageB === null || ageB > a.maxAge) return false;
  }
  if (b.minAge !== null && b.minAge !== undefined) {
    if (ageA === null || ageA < b.minAge) return false;
  }
  if (b.maxAge !== null && b.maxAge !== undefined) {
    if (ageA === null || ageA > b.maxAge) return false;
  }
  return true;
}

// ─────────────────────────────────────
// 최적 페어링 - min-cost 그리디 매칭
// 같은 (pinId + sportType) 그룹 내에서 레이팅 차이 기반 비용 최소화
// ─────────────────────────────────────

function findOptimalPairs(
  requests: WaitingRequest[],
  smallPool: boolean = false,
  blockedPairs: Set<string> = new Set(),
): [WaitingRequest, WaitingRequest][] {
  if (requests.length < 2) return [];

  const n = requests.length;
  const pairs: { i: number; j: number; cost: number; ratingDiff: number; effectiveRange: number; mannerAdj: number }[] = [];

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      // 동일 유저 매칭 방지
      if (requests[i].requesterId === requests[j].requesterId) continue;

      // 차단 관계 확인 — 차단된 쌍은 절대 매칭 불가
      const blockKey = [requests[i].requesterId, requests[j].requesterId].sort().join('::');
      if (blockedPairs.has(blockKey)) continue;

      // 성별/나이 호환성 — 즉시 매칭과 동일 정책
      if (!isCompatibleGenderAge(requests[i], requests[j])) continue;

      // 시간대 호환성 확인: 동일 슬롯이거나 한쪽이 ANY/null 일 때만 매칭 허용
      const slotI = requests[i].desiredTimeSlot;
      const slotJ = requests[j].desiredTimeSlot;
      const slotIAny = !slotI || slotI === 'ANY';
      const slotJAny = !slotJ || slotJ === 'ANY';
      if (!slotIAny && !slotJAny && slotI !== slotJ) continue;

      // 연패 조정: 3연패 이상이면 유효 레이팅 -50 적용
      const adjustedRatingI = requests[i].lossStreak >= 3
        ? requests[i].glickoRating - 50
        : requests[i].glickoRating;
      const adjustedRatingJ = requests[j].lossStreak >= 3
        ? requests[j].glickoRating - 50
        : requests[j].glickoRating;

      const rangeA = getEffectiveRange(requests[i]);
      const rangeB = getEffectiveRange(requests[j]);
      const effectiveRange = Math.max(rangeA, rangeB);

      const ratingDiff = Math.abs(adjustedRatingI - adjustedRatingJ);

      // 하드캡: 250 포인트 초과 → 절대 매칭 불가
      if (ratingDiff > 250) continue;

      // 소규모 풀(≤4명)이 아닌 경우에만 동적 범위 필터 적용
      if (!smallPool && ratingDiff > effectiveRange) continue;

      // 대기 시간 할인: 오래 기다릴수록 cost 감소
      const avgWaitRatio = (getWaitRatio(requests[i]) + getWaitRatio(requests[j])) / 2;
      const waitDiscount = 1.0 - 0.7 * avgWaitRatio;
      let cost = ratingDiff * waitDiscount;

      // 매너 cost 보정 (같은 핀 0.5 배수 적용 전에 합산)
      const mannerAdj = mannerCostAdjustment(requests[i], requests[j]);
      cost += mannerAdj;

      // 최근 상대 패널티: 24시간 내 동일 상대 재매칭 → +9999 비용
      if (isRecentOpponent(requests[i], requests[j])) {
        cost += 9999;
      }

      // 배치 게임 보너스: 배치 중인 플레이어는 비용 절반 (더 넓은 범위 수용)
      if (requests[i].isPlacement || requests[j].isPlacement) {
        cost *= 0.5;
      }

      pairs.push({ i, j, cost, ratingDiff, effectiveRange, mannerAdj });
    }
  }

  // 비용 오름차순 정렬
  pairs.sort((a, b) => a.cost - b.cost);

  // 그리디 매칭: 가장 낮은 비용 쌍부터 선택, 이미 매칭된 인덱스는 스킵
  const matched = new Set<number>();
  const result: [WaitingRequest, WaitingRequest][] = [];

  for (const pair of pairs) {
    if (matched.has(pair.i) || matched.has(pair.j)) continue;
    // 최근 상대 패널티만 남은 경우(cost >= 9999)는 불가 페어로 처리
    if (pair.cost >= 9999) {
      console.info(
        `[MatchingQueueWorker] Skipping recent opponent pair: ${requests[pair.i].sportsProfileId} <-> ${requests[pair.j].sportsProfileId}`,
      );
      continue;
    }

    matched.add(pair.i);
    matched.add(pair.j);
    result.push([requests[pair.i], requests[pair.j]]);

    const reqA = requests[pair.i];
    const reqB = requests[pair.j];
    console.info(
      `[MatchQueue] Matched: ratingDiff=${pair.ratingDiff} effectiveRange=${pair.effectiveRange.toFixed(1)} ` +
      `waitRatioA=${getWaitRatio(reqA).toFixed(2)} waitRatioB=${getWaitRatio(reqB).toFixed(2)} ` +
      `rdA=${reqA.glickoRd} rdB=${reqB.glickoRd} ` +
      `mannerTierA=${getMannerTier(reqA)} mannerTierB=${getMannerTier(reqB)} mannerAdj=${pair.mannerAdj}`,
    );
  }

  return result;
}

// ─────────────────────────────────────
// 매칭 후 양측 recentOpponentIds 업데이트
// 최근 5명 유지 (prepend 방식)
// ─────────────────────────────────────

async function updateRecentOpponents(profileId: string, opponentProfileId: string): Promise<void> {
  await AppDataSource.query(
    `UPDATE sports_profiles
     SET recent_opponent_ids = (
       SELECT array_agg(id) FROM (
         SELECT unnest(array_prepend($2::uuid, COALESCE(recent_opponent_ids, '{}'::uuid[]))) AS id
         LIMIT 5
       ) sub
     )
     WHERE id = $1`,
    [profileId, opponentProfileId],
  );
}

// ─────────────────────────────────────
// 매칭 큐 처리 메인 함수
// ─────────────────────────────────────

export async function processMatchingQueue(): Promise<boolean> {
  // AppDataSource가 초기화되지 않은 경우 초기화
  if (!AppDataSource.isInitialized) {
    await AppDataSource.initialize();
    console.info('[MatchingQueueWorker] AppDataSource initialized');
  }

  // 1) 모든 WAITING 상태의 매칭 요청 + Glicko-2 + 매너 필드 포함 스포츠 프로필 JOIN으로 조회
  //    match_request_ban_until > NOW() 인 요청은 임시 차단 중이므로 제외
  const waitingRequests = await AppDataSource.query<WaitingRequest[]>(
    `SELECT
      mr.id,
      mr.requester_id AS "requesterId",
      mr.sports_profile_id AS "sportsProfileId",
      mr.pin_id AS "pinId",
      mr.sport_type AS "sportType",
      mr.desired_date AS "desiredDate",
      mr.desired_time_slot AS "desiredTimeSlot",
      COALESCE(mr.is_casual, false) AS "isCasual",
      mr.created_at AS "createdAt",
      mr.expires_at AS "expiresAt",
      sp.current_score AS "currentScore",
      sp.glicko_rating AS "glickoRating",
      sp.glicko_rd AS "glickoRd",
      sp.glicko_volatility AS "glickoVolatility",
      sp.glicko_last_updated_at AS "glickoLastUpdatedAt",
      sp.is_placement AS "isPlacement",
      sp.loss_streak AS "lossStreak",
      sp.recent_opponent_ids AS "recentOpponentIds",
      sp.win_streak AS "winStreak",
      COALESCE(sp.manner_total, 0) AS "mannerTotal",
      COALESCE(sp.manner_count, 0) AS "mannerCount",
      u.gender AS "gender",
      u.birth_date AS "birthDate",
      mr.gender_preference AS "genderPreference",
      mr.min_age AS "minAge",
      mr.max_age AS "maxAge"
    FROM match_requests mr
    JOIN sports_profiles sp ON sp.id = mr.sports_profile_id
    LEFT JOIN users u ON u.id = mr.requester_id
    WHERE mr.status = 'WAITING'
      AND mr.expires_at > NOW()
      AND (sp.match_request_ban_until IS NULL OR sp.match_request_ban_until <= NOW())
    ORDER BY mr.created_at ASC`,
  );

  if (waitingRequests.length === 0) return false;

  // 2-a) 그룹핑 전, 각 요청의 RD를 마지막 게임 이후 경과일 기준으로 decay 적용
  for (const req of waitingRequests) {
    if (req.glickoLastUpdatedAt) {
      const daysSinceLastGame =
        (Date.now() - new Date(req.glickoLastUpdatedAt).getTime()) / (1000 * 60 * 60 * 24);
      const periods = Math.floor(daysSinceLastGame); // 1 period = 1 day
      if (periods > 0) {
        req.glickoRd = decayRD(req.glickoRd, req.glickoVolatility ?? 0.06, periods);
      }
    }
  }

  // 2-b) 차단 관계 조회 (차단된 유저 쌍은 매칭에서 제외)
  const allRequesterIds = [...new Set(waitingRequests.map(r => r.requesterId))];
  let blocks: UserBlock[] = [];
  if (allRequesterIds.length > 0) {
    blocks = await AppDataSource.getRepository(UserBlock).find({
      where: [
        { blockerId: In(allRequesterIds) },
        { blockedId: In(allRequesterIds) },
      ],
    });
  }
  const blockedPairs = new Set<string>();
  for (const b of blocks) {
    const key = [b.blockerId, b.blockedId].sort().join('::');
    blockedPairs.add(key);
  }

  // 2-c) (pinId, sportType, desiredDate, isCasual) 기준으로 그룹핑
  // 같은 날짜+모드(랭크/친선)끼리만 매칭되도록 그룹 키에 포함
  // 시간대는 ANY-호환 매칭이 필요하므로 페어 단계에서 검사한다.
  const groups = new Map<string, typeof waitingRequests>();
  for (const req of waitingRequests) {
    const dateKey = req.desiredDate ?? 'ANY';
    const casualKey = req.isCasual ? 'CASUAL' : 'RANKED';
    const key = `${req.pinId}::${req.sportType}::${dateKey}::${casualKey}`;
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key)!.push(req);
  }

  // 이미 이번 사이클에서 매칭된 requestId를 추적 (중복 매칭 방지)
  const matchedRequestIds = new Set<string>();

  // 3) 각 그룹에서 최적 페어 찾기 (min-cost 그리디 매칭)
  for (const [groupKey, requests] of groups) {
    if (requests.length < 2) continue;

    // 아직 매칭되지 않은 요청만 필터링
    const available = requests.filter((r) => !matchedRequestIds.has(r.id));
    if (available.length < 2) continue;

    // 최적 페어 목록 산출 (한 사이클에서 여러 쌍 동시 매칭 가능)
    // 4명 이하 소규모 풀이면 동적 범위 필터 비활성화 (하드캡 250만 적용)
    const smallPool = available.length <= 4;
    if (smallPool) {
      console.info(
        `[MatchingQueueWorker] Small pool (${available.length} users) for group: ${groupKey} — dynamic range disabled`,
      );
    }
    const optimalPairs = findOptimalPairs(available, smallPool, blockedPairs);

    if (optimalPairs.length === 0) {
      console.info(`[MatchingQueueWorker] No valid pairs found for group: ${groupKey}`);
      continue;
    }

    // 4) 각 페어에 대해 트랜잭션으로 매칭 생성
    for (const [pairA, pairB] of optimalPairs) {
      // 이번 사이클 내 다른 페어에서 이미 사용된 요청 스킵
      if (matchedRequestIds.has(pairA.id) || matchedRequestIds.has(pairB.id)) continue;

      try {
        let matchCreated = false;
        let createdMatchId = '';

        await AppDataSource.transaction(async (manager) => {
          // 최신 상태 확인 (race condition 방지)
          const [latestA, latestB] = await Promise.all([
            manager.findOne(MatchRequest, { where: { id: pairA.id } }),
            manager.findOne(MatchRequest, { where: { id: pairB.id } }),
          ]);

          if (
            !latestA || latestA.status !== MatchRequestStatus.WAITING ||
            !latestB || latestB.status !== MatchRequestStatus.WAITING
          ) {
            // 이미 다른 곳에서 처리된 요청 → 스킵
            console.info(
              `[MatchingQueueWorker] Skipping stale pair: ${pairA.id} / ${pairB.id}`,
            );
            return;
          }

          // ChatRoom 생성 (MATCH 타입)
          const chatRoom = manager.create(ChatRoom, {
            roomType: RoomType.MATCH,
          });
          const savedChatRoom = await manager.save(ChatRoom, chatRoom);

          // 시간대 resolve: ANY가 아닌 쪽 우선
          const slotA = pairA.desiredTimeSlot;
          const slotB = pairB.desiredTimeSlot;
          const resolvedSlot = (slotA && slotA !== 'ANY') ? slotA : (slotB && slotB !== 'ANY') ? slotB : (slotA || slotB || null);

          // Match 생성 (PENDING_ACCEPT 상태)
          const match = manager.create(Match, {
            matchRequestId: pairA.id,
            requesterProfileId: pairA.sportsProfileId,
            opponentProfileId: pairB.sportsProfileId,
            pinId: pairA.pinId,
            sportType: pairA.sportType as any,
            status: 'PENDING_ACCEPT' as any,
            chatRoomId: savedChatRoom.id,
            desiredDate: pairA.desiredDate ?? pairA.createdAt,
            scheduledDate: pairA.desiredDate ?? null,
            desiredTimeSlot: resolvedSlot as any,
          });
          const savedMatch = await manager.save(Match, match);

          // ChatRoom의 matchId 업데이트
          await manager.update(ChatRoom, savedChatRoom.id, { matchId: savedMatch.id });

          // MatchAcceptance 2개 생성 (expiresAt: 10분 후)
          const acceptExpiresAt = new Date(Date.now() + 10 * 60 * 1000);
          await manager.save(MatchAcceptance, [
            manager.create(MatchAcceptance, {
              matchId: savedMatch.id,
              userId: pairA.requesterId,
              accepted: null,
              expiresAt: acceptExpiresAt,
            }),
            manager.create(MatchAcceptance, {
              matchId: savedMatch.id,
              userId: pairB.requesterId,
              accepted: null,
              expiresAt: acceptExpiresAt,
            }),
          ]);

          // 두 MatchRequest를 MATCHED로 변경
          await manager
            .createQueryBuilder()
            .update(MatchRequest)
            .set({ status: MatchRequestStatus.MATCHED })
            .where('id IN (:...ids)', { ids: [pairA.id, pairB.id] })
            .execute();

          // 시스템 메시지 생성 ("매칭이 성사되었습니다!")
          const systemMessage = manager.create(Message, {
            chatRoomId: savedChatRoom.id,
            senderId: pairA.requesterId,
            messageType: MessageType.SYSTEM,
            content: '매칭이 성사되었습니다!',
          });
          await manager.save(Message, systemMessage);

          // ChatRoom lastMessageAt 업데이트
          await manager.update(ChatRoom, savedChatRoom.id, { lastMessageAt: new Date() });

          console.info(
            `[MatchingQueueWorker] Match created: ${savedMatch.id} | ${groupKey} | ` +
            `ratings: ${pairA.glickoRating.toFixed(0)} vs ${pairB.glickoRating.toFixed(0)}`,
          );

          matchCreated = true;
          createdMatchId = savedMatch.id;
        });

        if (matchCreated) {
          // 매칭 완료 처리된 ID 추적
          matchedRequestIds.add(pairA.id);
          matchedRequestIds.add(pairB.id);

          // 5) 매칭 후 양측 recentOpponentIds 업데이트 (트랜잭션 외부에서 실행)
          try {
            await Promise.all([
              updateRecentOpponents(pairA.sportsProfileId, pairB.sportsProfileId),
              updateRecentOpponents(pairB.sportsProfileId, pairA.sportsProfileId),
            ]);
          } catch (recentErr) {
            // recentOpponentIds 업데이트 실패는 매칭 자체를 롤백하지 않음 (비치명적)
            console.warn(
              `[MatchingQueueWorker] Failed to update recentOpponentIds for pair ${pairA.sportsProfileId} / ${pairB.sportsProfileId}:`,
              recentErr instanceof Error ? recentErr.message : recentErr,
            );
          }

          // 6) 양측에 알림 발송 (Redis pub/sub) + 실시간 매칭 성사 이벤트
          await Promise.all([
            redis.publish(
              'system_notification',
              JSON.stringify({
                userId: pairA.requesterId,
                type: 'MATCH_PENDING_ACCEPT',
                title: '매칭 상대를 찾았습니다!',
                body: '10분 내에 수락 여부를 결정해 주세요.',
                data: { matchId: createdMatchId, deepLink: `/matches/${createdMatchId}/accept` },
              }),
            ),
            redis.publish(
              'system_notification',
              JSON.stringify({
                userId: pairB.requesterId,
                type: 'MATCH_PENDING_ACCEPT',
                title: '매칭 상대를 찾았습니다!',
                body: '10분 내에 수락 여부를 결정해 주세요.',
                data: { matchId: createdMatchId, deepLink: `/matches/${createdMatchId}/accept` },
              }),
            ),
            // matchrequest:{requestId} 룸에서 대기 중인 클라이언트에게 실시간 전달
            redis.publish(
              'match_lifecycle',
              JSON.stringify({
                event: 'MATCH_FOUND',
                requestId: pairA.id,
                data: { matchId: createdMatchId, status: 'PENDING_ACCEPT' },
              }),
            ),
            redis.publish(
              'match_lifecycle',
              JSON.stringify({
                event: 'MATCH_FOUND',
                requestId: pairB.id,
                data: { matchId: createdMatchId, status: 'PENDING_ACCEPT' },
              }),
            ),
          ]);

          // 텔레그램 관리자 알림 — 매칭 잡힘 (워커 경로)
          try {
            const nicks = await AppDataSource.query<Array<{ id: string; nickname: string }>>(
              `SELECT id, nickname FROM users WHERE id = ANY($1::uuid[])`,
              [[pairA.requesterId, pairB.requesterId]],
            );
            const nickMap = new Map(nicks.map((n) => [n.id, n.nickname]));
            void sendAdminAlert(
              `🤝 <b>매칭 잡힘</b>\n` +
                `• ${escapeHtml(nickMap.get(pairA.requesterId) ?? pairA.requesterId)} vs ${escapeHtml(nickMap.get(pairB.requesterId) ?? pairB.requesterId)}\n` +
                `• matchId: <code>${escapeHtml(createdMatchId)}</code>`,
            );
          } catch (_) {
            /* 알림 실패는 무시 */
          }
        }
      } catch (err) {
        // 하나의 페어 매칭 실패가 전체 사이클을 중단시키지 않도록 에러 처리
        console.error(
          `[MatchingQueueWorker] Failed to create match for pair in group ${groupKey}:`,
          err instanceof Error ? err.message : err,
        );
      }
    }
  }

  return true;
}

// ─────────────────────────────────────
// BullMQ 이벤트 기반 매칭 큐
// ─────────────────────────────────────

import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';

const redisConnection = new IORedis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: null,
});

// 매칭 요청 시 즉시 처리할 큐
export const matchingQueue = new Queue('matching-process', {
  connection: redisConnection,
  defaultJobOptions: {
    removeOnComplete: 100,
    removeOnFail: 50,
  },
});

// 매칭 요청 생성 시 호출 — 즉시 매칭 시도 트리거
export async function triggerMatchingProcess(pinId: string, sportType: string): Promise<void> {
  await matchingQueue.add('process', { pinId, sportType }, {
    jobId: `match-${pinId}-${sportType}-${Date.now()}`,
  });
}

// ─────────────────────────────────────
// 독립 실행 모드 (PM2 worker로 직접 실행 시)
// ─────────────────────────────────────

if (process.env.STANDALONE_WORKER === 'true') {
  console.info('[MatchingQueueWorker] Starting in event-driven mode with 60s fallback');

  // BullMQ Worker — 매칭 요청 이벤트 즉시 처리
  const worker = new Worker('matching-process', async () => {
    await processMatchingQueue();
  }, {
    connection: redisConnection,
    concurrency: 1, // 동시 처리 1개 (매칭 충돌 방지)
    limiter: {
      max: 1,
      duration: 2000, // 최소 2초 간격 (연속 트리거 방어)
    },
  });

  worker.on('failed', (job, err) => {
    console.error(`[MatchingQueueWorker] Job ${job?.id} failed:`, err.message);
  });

  // 60초 fallback 폴링 (이벤트 누락 대비)
  setInterval(() => {
    processMatchingQueue().catch(console.error);
  }, 60000);

  // 초기 실행
  processMatchingQueue().catch(console.error);
}
