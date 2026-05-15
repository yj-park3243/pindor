import 'reflect-metadata';
import { Server as SocketServer } from 'socket.io';
import { Queue } from 'bullmq';
import { createApp } from './app.js';
import { env } from './config/env.js';
import { AppDataSource } from './config/database.js';
import { redis, bullmqRedis } from './config/redis.js';
import { initFirebase } from './config/firebase.js';
import { setupSocketGateway } from './modules/chat/chat.gateway.js';
import { NotificationService } from './modules/notifications/notification.service.js';

async function start(): Promise<void> {
  // ─────────────────────────────────────
  // TypeORM 데이터베이스 연결
  // ─────────────────────────────────────
  await AppDataSource.initialize();
  console.info('[Server] Database connected via TypeORM');

  // VERIFICATION_CODE MessageType enum 값 추가 (없으면)
  await AppDataSource.query(
    `DO $$ BEGIN ALTER TYPE "MessageType" ADD VALUE IF NOT EXISTS 'VERIFICATION_CODE'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;`
  ).catch((e: any) => console.warn('[Server] ALTER TYPE MessageType:', e.message));

  // EMAIL provider enum 값 추가 (없으면)
  await AppDataSource.query(
    `DO $$ BEGIN ALTER TYPE "SocialProvider" ADD VALUE IF NOT EXISTS 'EMAIL'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;`
  ).catch((e: any) => console.warn('[Server] ALTER TYPE SocialProvider:', e.message));

  // sports_profiles 테이블에 match_message 컬럼 추가 (없으면)
  await AppDataSource.query(
    `ALTER TABLE sports_profiles ADD COLUMN IF NOT EXISTS match_message VARCHAR(100);`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE sports_profiles:', e.message));

  // sports_profiles 테이블에 캐주얼 모드 컬럼 추가 (없으면)
  await AppDataSource.query(
    `ALTER TABLE sports_profiles
      ADD COLUMN IF NOT EXISTS casual_score INT NOT NULL DEFAULT 1000,
      ADD COLUMN IF NOT EXISTS casual_win INT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS casual_loss INT NOT NULL DEFAULT 0;`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE sports_profiles (casual):', e.message));

  // matches 테이블에 인증번호 컬럼 추가 (없으면)
  await AppDataSource.query(
    `ALTER TABLE matches
      ADD COLUMN IF NOT EXISTS requester_verification_code VARCHAR(4),
      ADD COLUMN IF NOT EXISTS opponent_verification_code VARCHAR(4);`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE matches (verification_code):', e.message));

  // match_requests 테이블에 is_casual 컬럼 추가 (없으면)
  await AppDataSource.query(
    `ALTER TABLE match_requests ADD COLUMN IF NOT EXISTS is_casual BOOLEAN NOT NULL DEFAULT false;`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE match_requests (is_casual):', e.message));

  // users 테이블에 KCP 본인인증 컬럼 추가 (없으면)
  await AppDataSource.query(
    `ALTER TABLE users
      ADD COLUMN IF NOT EXISTS phone_number VARCHAR(30) NULL,
      ADD COLUMN IF NOT EXISTS ci           VARCHAR(100) NULL,
      ADD COLUMN IF NOT EXISTS di           VARCHAR(100) NULL,
      ADD COLUMN IF NOT EXISTS real_name    VARCHAR(50) NULL,
      ADD COLUMN IF NOT EXISTS carrier      VARCHAR(20) NULL,
      ADD COLUMN IF NOT EXISTS is_verified  BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS verified_at  TIMESTAMPTZ NULL;`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE users (kcp):', e.message));

  // CI partial unique index (NULL 제외)
  await AppDataSource.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS uidx_users_ci ON users (ci) WHERE ci IS NOT NULL;`
  ).catch((e: any) => console.warn('[Server] CREATE INDEX uidx_users_ci:', e.message));

  // phone_number 인덱스 (NULL 제외)
  await AppDataSource.query(
    `CREATE INDEX IF NOT EXISTS idx_users_phone_number ON users (phone_number) WHERE phone_number IS NOT NULL;`
  ).catch((e: any) => console.warn('[Server] CREATE INDEX idx_users_phone_number:', e.message));

  // RequestType enum에 CASUAL 추가 (없으면)
  await AppDataSource.query(
    `DO $$ BEGIN ALTER TYPE "RequestType" ADD VALUE IF NOT EXISTS 'CASUAL'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;`
  ).catch((e: any) => console.warn('[Server] ALTER TYPE RequestType (CASUAL):', e.message));

  // pins 테이블에 search_keywords 컬럼 추가 (없으면)
  await AppDataSource.query(
    `ALTER TABLE pins ADD COLUMN IF NOT EXISTS search_keywords TEXT[] NOT NULL DEFAULT '{}';`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE pins (search_keywords):', e.message));

  // users: 디바이스 플랫폼(IOS/ANDROID) 기록 컬럼 추가 (없으면)
  // - X-Platform 헤더로 인증된 요청에서 set. NULL이면 옛 빌드 사용자 → iOS로 간주
  await AppDataSource.query(
    `ALTER TABLE users ADD COLUMN IF NOT EXISTS device_platform VARCHAR(10) NULL;`
  ).catch((e: any) => console.warn('[Server] ALTER TABLE users (device_platform):', e.message));

  // app_versions: 핸드폰 본인인증 강제 토글 컬럼 추가 (없으면)
  // - 신규 컬럼 추가 시점에만 platform별 기본값 시드: iOS=true, ANDROID=false (심사 대응)
  // - 컬럼이 이미 있으면 아무 동작 안 함 → 운영 중 변경한 값 보존
  await AppDataSource.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'app_versions' AND column_name = 'require_phone_verification'
      ) THEN
        ALTER TABLE app_versions ADD COLUMN require_phone_verification BOOLEAN;
        UPDATE app_versions
           SET require_phone_verification = CASE WHEN platform = 'ANDROID' THEN FALSE ELSE TRUE END;
        ALTER TABLE app_versions ALTER COLUMN require_phone_verification SET NOT NULL;
        ALTER TABLE app_versions ALTER COLUMN require_phone_verification SET DEFAULT TRUE;
      END IF;
    END $$;
  `).catch((e: any) => console.warn('[Server] ALTER TABLE app_versions (require_phone_verification):', e.message));

  // ─── 캠페인 알림 마이그레이션 ───
  // notification_settings: 캠페인 토글 컬럼 추가
  await AppDataSource.query(`
    ALTER TABLE notification_settings
      ADD COLUMN IF NOT EXISTS inactive_nudge   BOOLEAN NOT NULL DEFAULT TRUE,
      ADD COLUMN IF NOT EXISTS rank_drop_alert  BOOLEAN NOT NULL DEFAULT TRUE;
  `).catch((e: any) => console.warn('[Server] ALTER TABLE notification_settings (campaign):', e.message));

  // notification_campaign_logs 테이블 신설
  await AppDataSource.query(`
    CREATE TABLE IF NOT EXISTS notification_campaign_logs (
      id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id                   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      campaign_type             VARCHAR(40) NOT NULL,
      context                   JSONB NOT NULL DEFAULT '{}',
      sent_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      push_clicked_at           TIMESTAMPTZ,
      resulting_match_request_id UUID
    );
  `).catch((e: any) => console.warn('[Server] CREATE TABLE notification_campaign_logs:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_ncl_user_type_sent
      ON notification_campaign_logs(user_id, campaign_type, sent_at DESC);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_ncl_user_type_sent:', e.message));

  // ─── 노쇼 신고 시스템 마이그레이션 ───
  // noshow_reports 테이블 신설
  await AppDataSource.query(`
    CREATE TABLE IF NOT EXISTS noshow_reports (
      id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      match_id            UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
      reporter_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      reported_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      reported_profile_id UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
      status              VARCHAR(20) NOT NULL DEFAULT 'PENDING',
      evidence_urls       TEXT[] NOT NULL DEFAULT '{}',
      reporter_message    TEXT,
      admin_id            UUID REFERENCES admin_accounts(id),
      admin_decision_at   TIMESTAMPTZ,
      admin_memo          TEXT,
      applied_score_change INT,
      applied_ban_hours   INT,
      created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `).catch((e: any) => console.warn('[Server] CREATE TABLE noshow_reports:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_noshow_status_created
      ON noshow_reports(status, created_at DESC);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_noshow_status_created:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_noshow_reported_user
      ON noshow_reports(reported_user_id, status);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_noshow_reported_user:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_noshow_reporter
      ON noshow_reports(reporter_id, created_at DESC);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_noshow_reporter:', e.message));

  // manner_ratings 테이블 신설
  // UNIQUE: (match_id, rater_id, rated_user_id, source) — USER + NOSHOW_AUTO 같은 매칭에서 둘 다 가능
  await AppDataSource.query(`
    CREATE TABLE IF NOT EXISTS manner_ratings (
      id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      match_id          UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
      rater_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rated_user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rated_profile_id  UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
      score             INT NOT NULL CHECK (score BETWEEN 1 AND 5),
      source            VARCHAR(20) NOT NULL DEFAULT 'USER',
      noshow_report_id  UUID REFERENCES noshow_reports(id) ON DELETE SET NULL,
      voided_at         TIMESTAMPTZ,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(match_id, rater_id, rated_user_id, source)
    );
  `).catch((e: any) => console.warn('[Server] CREATE TABLE manner_ratings:', e.message));

  // 기존 환경에 UNIQUE(match_id, rater_id, rated_user_id)가 이미 있으면 source 포함으로 교체
  await AppDataSource.query(`
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'manner_ratings' AND c.contype = 'u'
          AND pg_get_constraintdef(c.oid) = 'UNIQUE (match_id, rater_id, rated_user_id)'
      ) THEN
        EXECUTE (
          SELECT 'ALTER TABLE manner_ratings DROP CONSTRAINT ' || quote_ident(c.conname)
          FROM pg_constraint c
          JOIN pg_class t ON t.oid = c.conrelid
          WHERE t.relname = 'manner_ratings' AND c.contype = 'u'
            AND pg_get_constraintdef(c.oid) = 'UNIQUE (match_id, rater_id, rated_user_id)'
          LIMIT 1
        );
        ALTER TABLE manner_ratings
          ADD CONSTRAINT manner_ratings_match_rater_rated_source_uk
          UNIQUE (match_id, rater_id, rated_user_id, source);
      END IF;
    END$$;
  `).catch((e: any) => console.warn('[Server] manner_ratings UNIQUE migration:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_manner_ratings_rated_profile
      ON manner_ratings(rated_profile_id, voided_at);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_manner_ratings_rated_profile:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_manner_ratings_match_rater
      ON manner_ratings(match_id, rater_id);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_manner_ratings_match_rater:', e.message));

  // sports_profiles: noshow_confirmed_count, match_request_ban_until 컬럼 추가
  await AppDataSource.query(`
    ALTER TABLE sports_profiles
      ADD COLUMN IF NOT EXISTS noshow_confirmed_count INT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS match_request_ban_until TIMESTAMPTZ NULL;
  `).catch((e: any) => console.warn('[Server] ALTER TABLE sports_profiles (noshow):', e.message));

  // users: noshow_report_ban_until + false_noshow_count 컬럼 추가
  await AppDataSource.query(`
    ALTER TABLE users
      ADD COLUMN IF NOT EXISTS noshow_report_ban_until TIMESTAMPTZ NULL,
      ADD COLUMN IF NOT EXISTS false_noshow_count INT NOT NULL DEFAULT 0;
  `).catch((e: any) => console.warn('[Server] ALTER TABLE users (noshow_report_ban):', e.message));

  // pin_ranking_snapshots 테이블 신설
  await AppDataSource.query(`
    CREATE TABLE IF NOT EXISTS pin_ranking_snapshots (
      id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      pin_id            UUID NOT NULL REFERENCES pins(id) ON DELETE CASCADE,
      sports_profile_id UUID NOT NULL REFERENCES sports_profiles(id) ON DELETE CASCADE,
      user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      sport_type        "SportType" NOT NULL,
      rank              INT NOT NULL,
      score             INT NOT NULL,
      snapshot_date     DATE NOT NULL,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(pin_id, sports_profile_id, sport_type, snapshot_date)
    );
  `).catch((e: any) => console.warn('[Server] CREATE TABLE pin_ranking_snapshots:', e.message));

  await AppDataSource.query(`
    CREATE INDEX IF NOT EXISTS idx_prs_user_date
      ON pin_ranking_snapshots(user_id, snapshot_date DESC);
  `).catch((e: any) => console.warn('[Server] CREATE INDEX idx_prs_user_date:', e.message));

  // UserStatus enum에 MERGED 추가 (없으면)
  await AppDataSource.query(
    `DO $$ BEGIN ALTER TYPE "UserStatus" ADD VALUE IF NOT EXISTS 'MERGED'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;`
  ).catch((e: any) => console.warn('[Server] ALTER TYPE UserStatus (MERGED):', e.message));

  // users: Firebase UID + 계정 병합 컬럼 추가 (없으면)
  await AppDataSource.query(`
    ALTER TABLE users
      ADD COLUMN IF NOT EXISTS firebase_uid          VARCHAR(128) NULL,
      ADD COLUMN IF NOT EXISTS merged_into_user_id   UUID        NULL REFERENCES users(id) ON DELETE SET NULL,
      ADD COLUMN IF NOT EXISTS merged_at             TIMESTAMPTZ NULL;
  `).catch((e: any) => console.warn('[Server] ALTER TABLE users (firebase/merge):', e.message));

  // firebase_uid unique index (NULL 제외)
  await AppDataSource.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS uidx_users_firebase_uid ON users(firebase_uid) WHERE firebase_uid IS NOT NULL;`
  ).catch((e: any) => console.warn('[Server] CREATE INDEX uidx_users_firebase_uid:', e.message));

  // ─────────────────────────────────────
  // Firebase 초기화
  // ─────────────────────────────────────
  initFirebase();

  // ─────────────────────────────────────
  // Fastify 앱 생성
  // ─────────────────────────────────────
  const fastify = await createApp();

  // ─────────────────────────────────────
  // Fastify 서버 시작 후 Socket.io 연결
  // ─────────────────────────────────────
  await fastify.listen({ port: env.PORT, host: '0.0.0.0' });

  console.info(`[Server] API running on port ${env.PORT}`);
  console.info(`[Server] Environment: ${env.NODE_ENV}`);
  if (env.NODE_ENV !== 'production') {
    console.info(`[Server] API Docs: http://localhost:${env.PORT}/docs`);
    console.info(`[Server] Health: http://localhost:${env.PORT}/health`);
  }

  // Socket.io를 Fastify의 내부 HTTP 서버에 직접 연결
  const io = new SocketServer(fastify.server, {
    path: '/ws',
    cors: {
      origin: env.CORS_ORIGIN.split(',').map((o) => o.trim()),
      credentials: true,
    },
    transports: ['websocket', 'polling'],
    pingTimeout: 30000,
    pingInterval: 15000,
  });

  // ─────────────────────────────────────
  // BullMQ 큐 초기화
  // ─────────────────────────────────────
  const pushQueue = new Queue('send-push', { connection: bullmqRedis });

  // ─────────────────────────────────────
  // NotificationService (Socket + Push 통합)
  // ─────────────────────────────────────
  const notificationService = new NotificationService(io, redis, pushQueue);

  // 전역으로 접근 가능하게 설정 (서비스 간 의존성 주입 대신 간단히 처리)
  (global as any).__notificationService = notificationService;
  (global as any).__io = io;

  // ─────────────────────────────────────
  // Socket.io 게이트웨이 설정
  // ─────────────────────────────────────
  setupSocketGateway(io, redis);

  // ─────────────────────────────────────
  // Redis pub/sub 구독 (워커→메인 서버 알림)
  // ─────────────────────────────────────
  const subClient = redis.duplicate();
  await subClient.subscribe('system_notification', 'push_notification', 'match_lifecycle', 'match_lifecycle_user', 'chat_room_message');

  subClient.on('message', async (channel, message) => {
    try {
      const payload = JSON.parse(message);

      if (channel === 'system_notification' || channel === 'push_notification') {
        await notificationService.send(payload);
      }

      // 매칭 라이프사이클 이벤트 → Socket.io 룸으로 직접 전달
      if (channel === 'match_lifecycle') {
        const { event, requestId, matchId, data } = payload;

        if (event === 'MATCH_FOUND' && requestId) {
          // 매칭 요청 룸에 매칭 성사 이벤트 전송
          io.to(`matchrequest:${requestId}`).emit('MATCH_FOUND', data);
        } else if (event === 'MATCH_STATUS_CHANGED' && matchId) {
          // 매칭 룸에 상태 변경 이벤트 전송
          io.to(`match:${matchId}`).emit('MATCH_STATUS_CHANGED', data);
        } else if (event === 'MATCH_MET_UPDATED' && matchId) {
          // 우리 만났어요 confirm 상태 변경 이벤트 전송
          io.to(`match:${matchId}`).emit('MATCH_MET_UPDATED', data);
        }
      }

      // 매칭 라이프사이클 — user 단위 발행 (매칭 룸 미참여자 보정)
      if (channel === 'match_lifecycle_user') {
        const { event, userId, data } = payload;
        if (event && userId) {
          io.to(`user:${userId}`).emit(event, data);
        }
      }

      // 채팅방 시스템 메시지 → 해당 채팅 룸으로 브로드캐스트
      if (channel === 'chat_room_message') {
        const { roomId, message: msgData } = payload;
        if (roomId && msgData) {
          io.to(`room:${roomId}`).emit('NEW_MESSAGE', msgData);
        }
      }
    } catch (err) {
      console.error('[Redis Sub] Message parse error:', err);
    }
  });

  // ─────────────────────────────────────
  // 캠페인 알림 워커 + Cron 등록
  // ─────────────────────────────────────
  {
    const { registerCampaignCronJobs } = await import('./workers/notification-campaign.worker.js');
    await registerCampaignCronJobs();
  }

  // ─────────────────────────────────────
  // 노쇼 신고 정리 워커 Cron 등록
  // ─────────────────────────────────────
  {
    const { registerNoshowCleanupCron } = await import('./workers/noshow-cleanup.worker.js');
    await registerNoshowCleanupCron();
  }

  // ─────────────────────────────────────
  // 매칭 수락 타임아웃 워커 (항상 활성화 — BullMQ delayed job 처리용)
  // ─────────────────────────────────────
  await import('./workers/match-accept-timeout.worker.js');

  // ─────────────────────────────────────
  // 경기 결과 자동 확정 워커 (항상 활성화 — 3분 delayed job 처리용)
  // ─────────────────────────────────────
  await import('./workers/game-auto-resolve.worker.js');

  // ─────────────────────────────────────
  // 주기적 작업 스케줄
  // ─────────────────────────────────────
  {
    const { processExpiredMatchRequests } = await import('./workers/match-expiry.worker.js');
    const { scheduleDeadlineWarnings } = await import('./workers/result-deadline.worker.js');
    const { rankingRefreshQueue } = await import('./workers/ranking-refresh.worker.js');
    const { processMatchingQueue } = await import('./workers/matching-queue.worker.js');
    const { processAutoResolveGames } = await import('./workers/auto-resolve.worker.js');

    // 5분마다 만료된 매칭 요청 처리
    setInterval(processExpiredMatchRequests, 5 * 60 * 1000);

    // 1시간마다 기한 임박 경기 알림
    setInterval(scheduleDeadlineWarnings, 60 * 60 * 1000);

    // 1시간마다 랭킹 갱신
    setInterval(async () => {
      await rankingRefreshQueue.add('refresh-all', {});
    }, 60 * 60 * 1000);

    // 매칭 큐 워커 (동적 폴링: WAITING 있으면 10초, 없으면 60초)
    let matchQueueInterval = 10000;
    const runMatchQueue = async () => {
      try {
        const hasWaiting = await processMatchingQueue();
        matchQueueInterval = hasWaiting ? 10000 : 60000;
      } catch (e) {
        console.error(e);
      }
      setTimeout(runMatchQueue, matchQueueInterval);
    };
    setTimeout(runMatchQueue, 10000);

    // 5분마다 경기 결과 자동 확정 백업 폴링 (3일 무입력 → 무승부, 3분 단측 → 채택)
    // BullMQ delayed job이 메인이지만, 누락 방지를 위한 백업
    setInterval(() => processAutoResolveGames().catch(console.error), 5 * 60 * 1000);
  }

  // ─────────────────────────────────────
  // Graceful Shutdown
  // ─────────────────────────────────────
  const shutdown = async (signal: string) => {
    console.info(`[Server] ${signal} received, shutting down...`);

    try {
      await fastify.close();
      await AppDataSource.destroy();
      await redis.quit();
      await subClient.quit();
      console.info('[Server] Gracefully shut down');
      process.exit(0);
    } catch {
      process.exit(1);
    }

    // 10초 후 강제 종료
    setTimeout(() => {
      console.error('[Server] Forced shutdown after timeout');
      process.exit(1);
    }, 10000);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  process.on('uncaughtException', (err) => {
    console.error('[Server] Uncaught exception:', err);
    process.exit(1);
  });

  process.on('unhandledRejection', (reason) => {
    console.error('[Server] Unhandled rejection:', reason);
    process.exit(1);
  });
}

start().catch((err) => {
  console.error('[Server] Failed to start:', err);
  process.exit(1);
});
