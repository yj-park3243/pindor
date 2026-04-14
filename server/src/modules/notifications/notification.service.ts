import { Server as SocketServer } from 'socket.io';
import { Redis } from 'ioredis';
import { Queue } from 'bullmq';
import { AppDataSource } from '../../config/database.js';
import { Notification } from '../../entities/notification.entity.js';
import { NotificationSettings } from '../../entities/notification-settings.entity.js';
import type { NotificationPayload, NotificationType } from '../../shared/types/index.js';
import type { ListNotificationsQuery } from './notification.schema.js';

// ─────────────────────────────────────
// 알림 설정 필드 매핑
// PRD 섹션 4.10.4
// ─────────────────────────────────────

const TYPE_TO_SETTING: Record<NotificationType, string> = {
  MATCH_FOUND: 'matchFound',
  MATCH_REQUEST_RECEIVED: 'matchRequest',
  MATCH_PENDING_ACCEPT: 'matchFound',
  MATCH_ACCEPTED: 'matchFound',
  MATCH_BOTH_ACCEPTED: 'matchFound',
  MATCH_REJECTED: 'matchFound',
  MATCH_EXPIRED: 'matchFound',
  MATCH_ACCEPT_TIMEOUT: 'matchFound',
  MATCH_WAITING_OPPONENT: 'matchFound',
  MATCH_CANCELLED: 'matchFound',
  MATCH_COMPLETED: 'matchFound',
  MATCH_NO_SHOW_PENALTY: 'matchFound',
  MATCH_NO_SHOW_COMPENSATION: 'matchFound',
  MATCH_FORFEIT: 'matchFound',
  MATCH_FORFEIT_WIN: 'matchFound',
  CHAT_MESSAGE: 'chatMessage',
  CHAT_IMAGE: 'chatMessage',
  CHAT_LOCATION: 'chatMessage',
  GAME_RESULT_SUBMITTED: 'gameResult',
  GAME_RESULT_CONFIRMED: 'gameResult',
  SCORE_UPDATED: 'scoreChange',
  TIER_CHANGED: 'scoreChange',
  RESULT_DEADLINE: 'gameResult',
  COMMUNITY_REPLY: 'communityReply',
};

export class NotificationService {
  private notificationRepo = AppDataSource.getRepository(Notification);
  private notificationSettingsRepo = AppDataSource.getRepository(NotificationSettings);

  constructor(
    private io: SocketServer,
    private redis: Redis,
    private pushQueue: Queue,
  ) {}

  // ─────────────────────────────────────
  // 단건 알림 발송 (PRD 4.10.4)
  // ─────────────────────────────────────

  async send(payload: NotificationPayload): Promise<void> {
    // 1) 사용자 알림 설정 확인
    const settingKey = TYPE_TO_SETTING[payload.type];
    const settings = await this.getUserSettings(payload.userId);

    if (settings && settingKey && !(settings as any)[settingKey]) {
      return; // 사용자가 해당 알림 OFF
    }

    // 2) DB 저장 (옵션)
    if (payload.saveToDb !== false) {
      const notification = this.notificationRepo.create({
        userId: payload.userId,
        type: payload.type,
        title: payload.title,
        body: payload.body,
        data: (payload.data ?? {}) as any,
      });
      await this.notificationRepo.save(notification);
    }

    // 3) Socket.io 실시간 전송 (앱 포그라운드)
    this.io.to(`user:${payload.userId}`).emit('notification', {
      type: payload.type,
      title: payload.title,
      body: payload.body,
      data: payload.data,
      createdAt: new Date().toISOString(),
    });

    // 4) FCM 푸시 (BullMQ 비동기 처리)
    await this.pushQueue.add(
      'send-push',
      {
        userId: payload.userId,
        type: payload.type,
        title: payload.title,
        body: payload.body,
        data: payload.data,
      },
      {
        attempts: 3,
        backoff: { type: 'exponential', delay: 1000 },
        removeOnComplete: 100,
        removeOnFail: 50,
      },
    );
  }

  // ─────────────────────────────────────
  // 복수 알림 일괄 발송
  // ─────────────────────────────────────

  async sendBulk(payloads: NotificationPayload[]): Promise<void> {
    await Promise.allSettled(payloads.map((p) => this.send(p)));
  }

  // ─────────────────────────────────────
  // 알림 목록 조회
  // ─────────────────────────────────────

  async getNotifications(userId: string, query: ListNotificationsQuery) {
    const { isRead, cursor, limit } = query;

    const qb = this.notificationRepo
      .createQueryBuilder('notification')
      .where('notification.user_id = :userId', { userId })
      .orderBy('notification.created_at', 'DESC')
      .take(limit + 1);

    if (isRead !== undefined) {
      qb.andWhere('notification.is_read = :isRead', { isRead });
    }

    if (cursor) {
      qb.andWhere('notification.created_at < :cursor', { cursor: new Date(cursor) });
    }

    const notifications = await qb.getMany();

    const hasMore = notifications.length > limit;
    const items = hasMore ? notifications.slice(0, limit) : notifications;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    // 읽지 않은 알림 수
    const unreadCount = await this.notificationRepo.count({
      where: { userId, isRead: false },
    });

    return { items, nextCursor, hasMore, unreadCount };
  }

  // ─────────────────────────────────────
  // 전체 읽음 처리
  // ─────────────────────────────────────

  async markAllRead(userId: string): Promise<void> {
    await this.notificationRepo.update(
      { userId, isRead: false },
      { isRead: true },
    );
  }

  // ─────────────────────────────────────
  // 단건 읽음 처리
  // ─────────────────────────────────────

  async markOneRead(userId: string, notificationId: string): Promise<void> {
    const notification = await this.notificationRepo.findOne({
      where: { id: notificationId, userId },
    });

    if (!notification) return;

    await this.notificationRepo.update(notificationId, { isRead: true });
  }

  // ─────────────────────────────────────
  // 알림 설정 업데이트
  // ─────────────────────────────────────

  async updateSettings(userId: string, settings: Record<string, unknown>): Promise<void> {
    const updateData: Partial<NotificationSettings> = {};

    if (settings.chatMessage !== undefined) updateData.chatMessage = settings.chatMessage as boolean;
    if (settings.matchFound !== undefined) updateData.matchFound = settings.matchFound as boolean;
    if (settings.matchRequest !== undefined) updateData.matchRequest = settings.matchRequest as boolean;
    if (settings.gameResult !== undefined) updateData.gameResult = settings.gameResult as boolean;
    if (settings.scoreChange !== undefined) updateData.scoreChange = settings.scoreChange as boolean;
    if (settings.communityReply !== undefined) updateData.communityReply = settings.communityReply as boolean;

    // doNotDisturbStart/End는 time 타입 (HH:MM 문자열) 그대로 저장
    if (settings.doNotDisturbStart !== undefined) {
      updateData.doNotDisturbStart = (settings.doNotDisturbStart as string | null);
    }
    if (settings.doNotDisturbEnd !== undefined) {
      updateData.doNotDisturbEnd = (settings.doNotDisturbEnd as string | null);
    }

    // upsert: 기존 설정이 있으면 update, 없으면 insert
    const existing = await this.notificationSettingsRepo.findOne({ where: { userId } });

    if (existing) {
      await this.notificationSettingsRepo.update({ userId }, updateData as any);
    } else {
      const newSettings = this.notificationSettingsRepo.create({ userId, ...updateData });
      await this.notificationSettingsRepo.save(newSettings);
    }

    // 캐시 무효화
    await this.redis.del(`notif_settings:${userId}`);
  }

  // ─────────────────────────────────────
  // 알림 설정 캐시 조회 (Redis 5분 TTL)
  // ─────────────────────────────────────

  private async getUserSettings(userId: string) {
    const cacheKey = `notif_settings:${userId}`;
    const cached = await this.redis.get(cacheKey);

    if (cached) {
      return JSON.parse(cached);
    }

    const settings = await this.notificationSettingsRepo.findOne({
      where: { userId },
    });

    if (settings) {
      await this.redis.setex(cacheKey, 300, JSON.stringify(settings));
    }

    return settings;
  }
}
