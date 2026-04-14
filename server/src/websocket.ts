/**
 * WebSocket 전용 서버 (별도 프로세스)
 * 프로덕션 환경에서 API 서버와 분리 실행
 *
 * 사용: npm run start:ws
 */

import 'reflect-metadata';
import { createServer } from 'http';
import { Server as SocketServer } from 'socket.io';
import { Queue } from 'bullmq';
import { env } from './config/env.js';
import { AppDataSource } from './config/database.js';
import { redis, bullmqRedis } from './config/redis.js';
import { initFirebase } from './config/firebase.js';
import { setupSocketGateway } from './modules/chat/chat.gateway.js';
import { NotificationService } from './modules/notifications/notification.service.js';

async function startWebSocketServer(): Promise<void> {
  // ─────────────────────────────────────
  // TypeORM 데이터베이스 연결
  // ─────────────────────────────────────
  await AppDataSource.initialize();
  console.info('[WS Server] Database connected via TypeORM');

  initFirebase();

  const httpServer = createServer();

  const io = new SocketServer(httpServer, {
    path: '/ws',
    cors: {
      origin: env.CORS_ORIGIN.split(',').map((o) => o.trim()),
      credentials: true,
    },
    transports: ['websocket', 'polling'],
    pingTimeout: 30000,
    pingInterval: 15000,
  });

  const pushQueue = new Queue('send-push', { connection: bullmqRedis });
  const notificationService = new NotificationService(io, redis, pushQueue);

  // Redis pub/sub 구독
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
      console.error('[WS Server] Message error:', err);
    }
  });

  setupSocketGateway(io, redis);

  httpServer.listen(env.WS_PORT, '0.0.0.0', () => {
    console.info(`[WS Server] WebSocket server running on port ${env.WS_PORT}`);
  });

  const shutdown = async (signal: string) => {
    console.info(`[WS Server] ${signal} received, shutting down...`);
    httpServer.close(async () => {
      await AppDataSource.destroy();
      await redis.quit();
      await subClient.quit();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

startWebSocketServer().catch((err) => {
  console.error('[WS Server] Failed to start:', err);
  process.exit(1);
});
