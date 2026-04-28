import { Queue, Worker, Job } from 'bullmq';
import { AppDataSource } from '../config/database.js';
import { bullmqRedis } from '../config/redis.js';
import { NotificationCampaignLog } from '../entities/notification-campaign-log.entity.js';
import { PinRankingSnapshot } from '../entities/pin-ranking-snapshot.entity.js';
import { RankingEntry } from '../entities/ranking-entry.entity.js';
import { NotificationSettings } from '../entities/notification-settings.entity.js';
import type { INotificationService } from '../shared/types/index.js';
import type { CampaignType } from '../entities/notification-campaign-log.entity.js';

// ─────────────────────────────────────
// 환경변수로 cron 오버라이드 (테스트 편의)
// 기본값: KST 18:00 = UTC 09:00 / KST 00:00 = UTC 15:00
// ─────────────────────────────────────
const CRON_18KST = process.env.CAMPAIGN_DAILY_CRON ?? '0 9 * * *';
const CRON_SNAPSHOT = process.env.CAMPAIGN_SNAPSHOT_CRON ?? '0 15 * * *';

// 한 번에 처리할 유저 수 (부하 분산)
const CHUNK_SIZE = 100;
const CHUNK_DELAY_MS = 100;

// ─────────────────────────────────────
// 메시지 변형 (5종, 직전 발송 본문 중복 회피)
// ─────────────────────────────────────

type MessageVariant = { title: string; body: string };

const INACTIVE_2D_MESSAGES: MessageVariant[] = [
  { title: '오랜만이에요!', body: '마지막 경기 후 며칠이 지났어요. 오늘 한 판 어때요?' },
  { title: '상대가 기다려요', body: '새로 들어온 상대가 근처에 있어요. 지금 바로 찾아볼까요?' },
  { title: '요즘 뭐 해요?', body: '매칭을 안 한 지 꽤 됐네요. 한 판으로 다시 달려요!' },
  { title: '실력이 녹슬기 전에', body: '잠깐 쉬어가도 괜찮아요. 이제 슬슬 복귀할 때!' },
  { title: '근처 핀이 핫해요 🔥', body: '동네 핀에 새 상대들이 활동 중이에요. 오늘 도전해 보는 건 어때요?' },
];

const NEW_USER_NUDGE_MESSAGES: MessageVariant[] = [
  { title: '첫 매칭, 도전해 봐요!', body: '아직 첫 매칭 전이에요. 근처 상대를 찾아볼까요?' },
  { title: '근처 핀이 기다려요', body: '우리 동네 핀에 여러 명이 활동 중이에요. 지금 도전!' },
  { title: '시작이 반이에요', body: '처음이라 어색해도 괜찮아요. 캐주얼 매칭으로 가볍게 시작해 봐요.' },
  { title: '같이 해봐요!', body: '가입한 지 며칠 됐네요. 첫 매칭으로 첫 점수를 올려볼까요?' },
  { title: '지금이 딱이에요!', body: '주변에 매칭을 기다리는 상대가 있어요. 놓치기 전에 빠르게 도전해 봐요.' },
];

const RANK_DROP_MESSAGES: MessageVariant[] = [
  { title: '랭킹이 떨어졌어요', body: '핀 랭킹이 {drop}위 하락했어요. 한 판으로 바로 회복해요!' },
  { title: '순위 하락 알림', body: '{sportType} 랭킹이 {rankBefore}위에서 {rankAfter}위로 내려갔어요. 다시 올려볼까요? 🔥' },
  { title: '지금 반격할 때!', body: '랭킹이 잠깐 빠졌어요. 오늘 한 경기로 되찾아 봐요.' },
  { title: '순위를 지켜요!', body: '{sportType} 핀에서 {drop}단계 밀렸어요. 지금 바로 대결해 봐요.' },
  { title: '랭킹 회복 찬스!', body: '잠깐 밀렸지만 괜찮아요. 오늘 매칭으로 다시 치고 올라가요.' },
];

/**
 * 메시지 변형 중 직전 발송 본문과 다른 것을 랜덤 선택
 */
function pickVariant(variants: MessageVariant[], lastBody: string | null): MessageVariant {
  const filtered = variants.filter((v) => v.body !== lastBody);
  const pool = filtered.length > 0 ? filtered : variants;
  return pool[Math.floor(Math.random() * pool.length)];
}

/**
 * 종목 한글명 변환
 */
function sportTypeKo(sportType: string): string {
  const map: Record<string, string> = {
    GOLF: '골프',
    BILLIARDS: '당구',
    BILLIARDS_4BALL: '4구',
    BILLIARDS_3CUSHION: '3쿠션',
    TENNIS: '테니스',
    TABLE_TENNIS: '탁구',
    BADMINTON: '배드민턴',
    BOWLING: '볼링',
    SOCCER: '축구',
    BASKETBALL: '농구',
    BASEBALL: '야구',
    ROCK_PAPER_SCISSORS: '가위바위보',
    ARM_WRESTLING: '팔씨름',
  };
  return map[sportType] ?? sportType;
}

// sleep 헬퍼
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

// ─────────────────────────────────────
// BullMQ Queue 정의
// ─────────────────────────────────────

export const campaignQueue = new Queue('notification-campaign', {
  connection: bullmqRedis,
  defaultJobOptions: {
    removeOnComplete: { count: 20 },
    removeOnFail: { count: 50 },
  },
});

// ─────────────────────────────────────
// 글로벌 가드: 오늘 이미 캠페인 발송됐는지 확인
// ─────────────────────────────────────

async function hasSentToday(userId: string): Promise<boolean> {
  const logRepo = AppDataSource.getRepository(NotificationCampaignLog);
  const count = await logRepo
    .createQueryBuilder('log')
    .where('log.user_id = :userId', { userId })
    .andWhere("log.sent_at::date = CURRENT_DATE")
    .getCount();
  return count > 0;
}

/**
 * 캠페인 로그 기록
 */
async function recordLog(
  userId: string,
  campaignType: CampaignType,
  context: Record<string, unknown>,
): Promise<void> {
  const logRepo = AppDataSource.getRepository(NotificationCampaignLog);
  const log = logRepo.create({ userId, campaignType, context });
  await logRepo.save(log);
}

// ─────────────────────────────────────
// A. inactive-2d 처리 로직
// ─────────────────────────────────────

async function processInactive2d(notificationService: INotificationService): Promise<void> {
  const logRepo = AppDataSource.getRepository(NotificationCampaignLog);
  const settingsRepo = AppDataSource.getRepository(NotificationSettings);

  // 마지막 매칭 신청 후 2일 이상 경과 + 한 번이라도 신청한 적 있는 활성 유저 조회
  const candidates = await AppDataSource.query<Array<{ user_id: string }>>(`
    SELECT u.id AS user_id
    FROM users u
    WHERE u.status = 'ACTIVE'
      AND EXISTS (
        SELECT 1 FROM match_requests mr WHERE mr.requester_id = u.id
      )
      AND COALESCE(
        (SELECT MAX(mr2.created_at) FROM match_requests mr2 WHERE mr2.requester_id = u.id),
        '1970-01-01'
      ) < NOW() - INTERVAL '2 days'
      AND NOT EXISTS (
        SELECT 1 FROM notification_campaign_logs ncl
        WHERE ncl.user_id = u.id
          AND ncl.campaign_type = 'INACTIVE_2D'
          AND ncl.sent_at > NOW() - INTERVAL '3 days'
      )
  `);

  console.info(`[CampaignWorker] inactive-2d candidates: ${candidates.length}`);

  for (let i = 0; i < candidates.length; i += CHUNK_SIZE) {
    const chunk = candidates.slice(i, i + CHUNK_SIZE);

    for (const row of chunk) {
      const userId = row.user_id;

      // 글로벌 가드: 오늘 이미 다른 캠페인 발송됐으면 스킵
      if (await hasSentToday(userId)) continue;

      // 알림 설정 확인
      const settings = await settingsRepo.findOne({ where: { userId } });
      if (settings && settings.inactiveNudge === false) continue;

      // 직전 발송 본문 조회 (중복 회피)
      const lastLog = await logRepo.findOne({
        where: { userId, campaignType: 'INACTIVE_2D' },
        order: { sentAt: 'DESC' },
        select: ['context'],
      });
      const lastBody = (lastLog?.context?.body as string) ?? null;

      const variant = pickVariant(INACTIVE_2D_MESSAGES, lastBody);

      try {
        await notificationService.send({
          userId,
          type: 'CAMPAIGN',
          title: variant.title,
          body: variant.body,
          data: { deepLink: '/matches/create', campaignType: 'INACTIVE_2D' },
        });

        await recordLog(userId, 'INACTIVE_2D', {
          body: variant.body,
          sentAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error(`[CampaignWorker] inactive-2d send error for ${userId}:`, (err as Error).message);
      }
    }

    if (i + CHUNK_SIZE < candidates.length) {
      await sleep(CHUNK_DELAY_MS);
    }
  }

  console.info('[CampaignWorker] inactive-2d done');
}

// ─────────────────────────────────────
// B. new-user-nudge 처리 로직
// ─────────────────────────────────────

async function processNewUserNudge(notificationService: INotificationService): Promise<void> {
  const logRepo = AppDataSource.getRepository(NotificationCampaignLog);
  const settingsRepo = AppDataSource.getRepository(NotificationSettings);

  // 가입 후 3~12일 사이 + 아직 매칭 신청 없음 + 3회 미만 발송 + 3일 쿨다운 미경과
  const candidates = await AppDataSource.query<Array<{ user_id: string }>>(`
    SELECT u.id AS user_id
    FROM users u
    WHERE u.status = 'ACTIVE'
      AND NOT EXISTS (
        SELECT 1 FROM match_requests mr WHERE mr.requester_id = u.id
      )
      AND u.created_at < NOW() - INTERVAL '3 days'
      AND u.created_at > NOW() - INTERVAL '12 days'
      AND (
        SELECT COUNT(*) FROM notification_campaign_logs ncl
        WHERE ncl.user_id = u.id AND ncl.campaign_type = 'NEW_USER_NUDGE'
      ) < 3
      AND NOT EXISTS (
        SELECT 1 FROM notification_campaign_logs ncl2
        WHERE ncl2.user_id = u.id
          AND ncl2.campaign_type = 'NEW_USER_NUDGE'
          AND ncl2.sent_at > NOW() - INTERVAL '3 days'
      )
  `);

  console.info(`[CampaignWorker] new-user-nudge candidates: ${candidates.length}`);

  for (let i = 0; i < candidates.length; i += CHUNK_SIZE) {
    const chunk = candidates.slice(i, i + CHUNK_SIZE);

    for (const row of chunk) {
      const userId = row.user_id;

      if (await hasSentToday(userId)) continue;

      // 알림 설정 확인 (inactive_nudge로 통합 관리)
      const settings = await settingsRepo.findOne({ where: { userId } });
      if (settings && settings.inactiveNudge === false) continue;

      const lastLog = await logRepo.findOne({
        where: { userId, campaignType: 'NEW_USER_NUDGE' },
        order: { sentAt: 'DESC' },
        select: ['context'],
      });
      const lastBody = (lastLog?.context?.body as string) ?? null;
      const sendCount = lastLog ? ((lastLog.context?.sendCount as number) ?? 0) + 1 : 1;

      const variant = pickVariant(NEW_USER_NUDGE_MESSAGES, lastBody);

      try {
        await notificationService.send({
          userId,
          type: 'CAMPAIGN',
          title: variant.title,
          body: variant.body,
          data: { deepLink: '/matches/create', campaignType: 'NEW_USER_NUDGE' },
        });

        await recordLog(userId, 'NEW_USER_NUDGE', {
          body: variant.body,
          sendCount,
          sentAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error(`[CampaignWorker] new-user-nudge send error for ${userId}:`, (err as Error).message);
      }
    }

    if (i + CHUNK_SIZE < candidates.length) {
      await sleep(CHUNK_DELAY_MS);
    }
  }

  console.info('[CampaignWorker] new-user-nudge done');
}

// ─────────────────────────────────────
// C. rank-drop 처리 로직
// ─────────────────────────────────────

async function processRankDrop(notificationService: INotificationService): Promise<void> {
  const logRepo = AppDataSource.getRepository(NotificationCampaignLog);
  const settingsRepo = AppDataSource.getRepository(NotificationSettings);

  // 어제 스냅샷 vs 현재 ranking_entries 비교 (5위 이상 하락)
  type RankDropRow = {
    user_id: string;
    sport_type: string;
    pin_id: string;
    rank_yesterday: number;
    rank_today: number;
    drop: number;
  };

  const drops = await AppDataSource.query<RankDropRow[]>(`
    SELECT
      prs.user_id,
      prs.sport_type,
      prs.pin_id,
      prs.rank AS rank_yesterday,
      re.rank  AS rank_today,
      (re.rank - prs.rank) AS drop
    FROM pin_ranking_snapshots prs
    JOIN ranking_entries re
      ON  re.pin_id           = prs.pin_id
      AND re.sports_profile_id = prs.sports_profile_id
      AND re.sport_type       = prs.sport_type
    WHERE prs.snapshot_date = CURRENT_DATE - INTERVAL '1 day'
      AND (re.rank - prs.rank) >= 5
  `);

  console.info(`[CampaignWorker] rank-drop candidates: ${drops.length}`);

  for (let i = 0; i < drops.length; i += CHUNK_SIZE) {
    const chunk = drops.slice(i, i + CHUNK_SIZE);

    for (const row of chunk) {
      const { user_id: userId, sport_type: sportType, pin_id: pinId, rank_yesterday: rankBefore, rank_today: rankAfter, drop } = row;

      if (await hasSentToday(userId)) continue;

      // 알림 설정 확인
      const settings = await settingsRepo.findOne({ where: { userId } });
      if (settings && settings.rankDropAlert === false) continue;

      // 3일 쿨다운 체크 (단, 회복 시 무시)
      const lastRankDropLog = await logRepo.findOne({
        where: { userId, campaignType: 'RANK_DROP' },
        order: { sentAt: 'DESC' },
        select: ['context', 'sentAt'],
      });

      if (lastRankDropLog) {
        const rankAtSend = lastRankDropLog.context?.rankAtSend as number | undefined;
        const sentAt = lastRankDropLog.sentAt;
        const daysSinceLast = (Date.now() - sentAt.getTime()) / (1000 * 60 * 60 * 24);

        // 회복 이력 감지: 어제(rankBefore) 시점에 마지막 발송 시점보다 순위가 좋아졌다(더 작아졌다)
        // → 한 번 회복했었음. 오늘 다시 떨어졌으니 쿨다운 무시하고 알림 발송.
        // (SQL 단에서 이미 오늘 5위 이상 하락한 케이스만 통과되므로, 이 시점에 도달했다 = 다시 떨어졌다)
        const hasRecoveredHistory =
          rankAtSend !== undefined && rankBefore < rankAtSend;

        // 회복 이력 없고 3일 쿨다운 안 지났으면 스킵
        if (daysSinceLast < 3 && !hasRecoveredHistory) continue;
      }

      const lastBody = (lastRankDropLog?.context?.body as string) ?? null;
      const variant = pickVariant(RANK_DROP_MESSAGES, lastBody);

      // 메시지 변수 치환
      const body = variant.body
        .replace('{sportType}', sportTypeKo(sportType))
        .replace('{rankBefore}', String(rankBefore))
        .replace('{rankAfter}', String(rankAfter))
        .replace('{drop}', String(drop));

      const deepLink = `/matches/create?sportType=${sportType}`;

      try {
        await notificationService.send({
          userId,
          type: 'CAMPAIGN',
          title: variant.title,
          body,
          data: { deepLink, campaignType: 'RANK_DROP', sportType, pinId },
        });

        await recordLog(userId, 'RANK_DROP', {
          body,
          sportType,
          pinId,
          rankAtSend: rankAfter,   // 이 시점의 현재 순위 저장 (회복 감지용)
          rankBefore,
          rankAfter,
          drop,
          sentAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error(`[CampaignWorker] rank-drop send error for ${userId}:`, (err as Error).message);
      }
    }

    if (i + CHUNK_SIZE < drops.length) {
      await sleep(CHUNK_DELAY_MS);
    }
  }

  console.info('[CampaignWorker] rank-drop done');
}

// ─────────────────────────────────────
// D. ranking-snapshot 처리 로직
// 매일 KST 00:00 (UTC 15:00)에 ranking_entries 전체를 pin_ranking_snapshots에 복사
// ─────────────────────────────────────

async function processRankingSnapshot(): Promise<void> {
  console.info('[CampaignWorker] ranking-snapshot start');
  // ON CONFLICT DO NOTHING으로 같은 날 중복 실행 방어
  await AppDataSource.query(`
    INSERT INTO pin_ranking_snapshots (id, pin_id, sports_profile_id, user_id, sport_type, rank, score, snapshot_date, created_at)
    SELECT
      gen_random_uuid(),
      re.pin_id,
      re.sports_profile_id,
      sp.user_id,
      re.sport_type,
      re.rank,
      re.score,
      CURRENT_DATE,
      NOW()
    FROM ranking_entries re
    JOIN sports_profiles sp ON sp.id = re.sports_profile_id
    ON CONFLICT (pin_id, sports_profile_id, sport_type, snapshot_date)
      DO NOTHING
  `);

  console.info('[CampaignWorker] ranking-snapshot done');
}

// ─────────────────────────────────────
// BullMQ Worker — 캠페인 잡 처리
// 우선순위: rank-drop > inactive-2d > new-user-nudge
// ─────────────────────────────────────

export const campaignWorker = new Worker(
  'notification-campaign',
  async (job: Job) => {
    const notificationService = (global as any).__notificationService as INotificationService | undefined;
    if (!notificationService) {
      console.warn('[CampaignWorker] notificationService not initialized, skipping');
      return;
    }

    switch (job.name) {
      case 'ranking-snapshot':
        await processRankingSnapshot();
        break;

      case 'rank-drop':
        await processRankDrop(notificationService);
        break;

      case 'inactive-2d':
        await processInactive2d(notificationService);
        break;

      case 'new-user-nudge':
        await processNewUserNudge(notificationService);
        break;

      default:
        console.warn(`[CampaignWorker] Unknown job name: ${job.name}`);
    }
  },
  {
    connection: bullmqRedis,
    concurrency: 1, // 캠페인 잡은 순차 실행 (글로벌 가드 정합성 보장)
  },
);

campaignWorker.on('completed', (job) => {
  console.info(`[CampaignWorker] Job '${job.name}' (${job.id}) completed`);
});

campaignWorker.on('failed', (job, err) => {
  console.error(`[CampaignWorker] Job '${job?.name}' (${job?.id}) failed:`, err.message);
});

// ─────────────────────────────────────
// Cron 등록 함수 (server.ts에서 호출)
// ─────────────────────────────────────

export async function registerCampaignCronJobs(): Promise<void> {
  // 우선순위 순서로 등록 (rank-drop → inactive-2d → new-user-nudge)
  // BullMQ에서 같은 큐에 concurrency:1로 순차 처리되므로 순서 의미 있음

  await campaignQueue.add('ranking-snapshot', {}, {
    repeat: { pattern: CRON_SNAPSHOT },
    jobId: 'cron-ranking-snapshot',
  });

  await campaignQueue.add('rank-drop', {}, {
    repeat: { pattern: CRON_18KST },
    jobId: 'cron-rank-drop',
  });

  await campaignQueue.add('inactive-2d', {}, {
    repeat: { pattern: CRON_18KST },
    jobId: 'cron-inactive-2d',
  });

  await campaignQueue.add('new-user-nudge', {}, {
    repeat: { pattern: CRON_18KST },
    jobId: 'cron-new-user-nudge',
  });

  console.info(
    `[CampaignWorker] Cron jobs registered — snapshot: ${CRON_SNAPSHOT}, campaign: ${CRON_18KST}`,
  );
}
