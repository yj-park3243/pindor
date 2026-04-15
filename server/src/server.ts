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
  await subClient.subscribe('system_notification', 'push_notification', 'match_lifecycle', 'chat_room_message');

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

    // 매칭 큐 워커 (10초마다)
    setInterval(() => processMatchingQueue().catch(console.error), 10000);

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
