import { Worker, Job } from 'bullmq';
import * as admin from 'firebase-admin';
import { AppDataSource } from '../config/database.js';
import { DeviceToken } from '../entities/device-token.entity.js';
import { Notification } from '../entities/notification.entity.js';
import { NotificationSettings } from '../entities/notification-settings.entity.js';
import { redis, bullmqRedis } from '../config/redis.js';
import { initFirebase, getMessaging, isFirebaseEnabled } from '../config/firebase.js';
import type { PushJobData, NotificationType } from '../shared/types/index.js';

// ─────────────────────────────────────
// Firebase 초기화
// ─────────────────────────────────────

initFirebase();

// ─────────────────────────────────────
// Push Worker (PRD 섹션 4.10.5)
// ─────────────────────────────────────

export const pushWorker = new Worker<PushJobData>(
  'send-push',
  async (job: Job<PushJobData>) => {
    const { userId, type, title, body, data } = job.data;

    try {
      // 0) Firebase 미설정 시 스킵
      if (!isFirebaseEnabled()) {
        console.info(`[PushWorker] Firebase disabled — skipping push for ${userId}`);
        return;
      }

      // 1) 방해금지 시간 확인
      const settings = await getNotificationSettings(userId);
      if (isDoNotDisturbTime(settings)) {
        console.info(`[PushWorker] Skipped (DND): ${userId}`);
        return;
      }

      // 2) 채팅 메시지: 사용자가 해당 채팅방에 접속 중이면 푸시 스킵
      if (type === 'CHAT_MESSAGE' || type === 'CHAT_IMAGE') {
        const activeRoom = await redis.get(`user_active_room:${userId}`);
        if (activeRoom && activeRoom === data?.roomId) {
          console.info(`[PushWorker] Skipped (active room): ${userId}`);
          return;
        }
      }

      // 3) 디바이스 토큰 조회
      const deviceTokenRepo = AppDataSource.getRepository(DeviceToken);
      const tokens = await deviceTokenRepo.find({
        where: { userId, isActive: true },
      });

      if (tokens.length === 0) {
        console.info(`[PushWorker] No active tokens: ${userId}`);
        return;
      }

      // 4) 미읽은 알림 수 (iOS badge)
      const notificationRepo = AppDataSource.getRepository(Notification);
      const unreadCount = await notificationRepo.count({
        where: { userId, isRead: false },
      });

      // 5) FCM 멀티캐스트 발송
      const message: admin.messaging.MulticastMessage = {
        tokens: tokens.map((t) => t.token),
        notification: { title, body },
        data: {
          type,
          deepLink: data?.deepLink ?? '',
          ...(data ?? {}),
        },
        android: {
          priority: 'high',
          notification: {
            channelId: getAndroidChannel(type),
            sound: 'default',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: unreadCount,
              'mutable-content': 1,
              'thread-id': getThreadId(type, data),
            } as any,
          },
        },
      };

      const messaging = getMessaging();
      if (!messaging) {
        console.info(`[PushWorker] Messaging not available — skipping`);
        return;
      }
      const response = await messaging.sendEachForMulticast(message);

      console.info(
        `[PushWorker] Sent to ${tokens.length} devices: ${response.successCount} success, ${response.failureCount} failed`,
      );

      // 6) 실패 토큰 비활성화
      const failedTokenUpdates: Promise<any>[] = [];
      response.responses.forEach((resp, idx) => {
        if (
          !resp.success &&
          resp.error?.code === 'messaging/registration-token-not-registered'
        ) {
          failedTokenUpdates.push(
            deviceTokenRepo
              .update({ id: tokens[idx].id }, { isActive: false })
              .catch(console.error),
          );
        }
      });

      if (failedTokenUpdates.length > 0) {
        await Promise.allSettled(failedTokenUpdates);
        console.info(`[PushWorker] Deactivated ${failedTokenUpdates.length} expired tokens`);
      }
    } catch (err) {
      console.error('[PushWorker] Error:', err);
      throw err; // BullMQ 재시도를 위해 에러 재던짐
    }
  },
  {
    connection: bullmqRedis,
    concurrency: 10,
  },
);

pushWorker.on('completed', (job) => {
  console.info(`[PushWorker] Job ${job.id} completed`);
});

pushWorker.on('failed', (job, err) => {
  console.error(`[PushWorker] Job ${job?.id} failed:`, err.message);
});

// ─────────────────────────────────────
// 헬퍼 함수
// ─────────────────────────────────────

function getAndroidChannel(type: NotificationType): string {
  if (type.startsWith('CHAT_')) return 'chat_messages';
  if (type.startsWith('MATCH_')) return 'match_alerts';
  return 'general';
}

function getThreadId(type: NotificationType, data?: Record<string, string>): string {
  if (type.startsWith('CHAT_') && data?.roomId) return `chat_${data.roomId}`;
  if (type.startsWith('MATCH_') && data?.matchId) return `match_${data.matchId}`;
  return type;
}

async function getNotificationSettings(userId: string): Promise<NotificationSettings | null> {
  const settingsRepo = AppDataSource.getRepository(NotificationSettings);
  return settingsRepo.findOne({ where: { userId } });
}

function isDoNotDisturbTime(settings: NotificationSettings | null): boolean {
  if (!settings?.doNotDisturbStart || !settings?.doNotDisturbEnd) return false;

  const now = new Date();
  const current = now.getHours() * 60 + now.getMinutes();

  // doNotDisturbStart/End는 time 타입 — "HH:MM:SS" 또는 "HH:MM" 형식
  const parseTime = (t: string): number => {
    const [h, m] = t.split(':').map(Number);
    return h * 60 + m;
  };

  const start = parseTime(settings.doNotDisturbStart);
  const end = parseTime(settings.doNotDisturbEnd);

  // 자정을 넘기는 경우 (예: 23:00 ~ 08:00)
  if (start > end) return current >= start || current < end;
  return current >= start && current < end;
}
