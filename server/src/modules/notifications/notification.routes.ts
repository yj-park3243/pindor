import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import { Notification } from '../../entities/notification.entity.js';
import { NotificationSettings } from '../../entities/notification-settings.entity.js';
import { DeviceToken } from '../../entities/device-token.entity.js';
import { DevicePlatform } from '../../entities/enums.js';
import {
  listNotificationsQuerySchema,
  registerPushTokenSchema,
  deletePushTokenSchema,
  updateNotificationSettingsSchema,
  type ListNotificationsQuery,
  type RegisterPushTokenDto,
  type DeletePushTokenDto,
  type UpdateNotificationSettingsDto,
} from './notification.schema.js';
import { redis } from '../../config/redis.js';

export async function notificationRoutes(fastify: FastifyInstance): Promise<void> {
  const notificationRepo = AppDataSource.getRepository(Notification);
  const notificationSettingsRepo = AppDataSource.getRepository(NotificationSettings);
  const deviceTokenRepo = AppDataSource.getRepository(DeviceToken);

  // ─── GET /notifications ───
  fastify.get(
    '/notifications',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Notifications'],
        summary: '알림 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Querystring: ListNotificationsQuery }>,
      reply: FastifyReply,
    ) => {
      const query = listNotificationsQuerySchema.parse(request.query);
      const userId = request.user.userId;

      const qb = notificationRepo
        .createQueryBuilder('notification')
        .where('notification.user_id = :userId', { userId })
        .orderBy('notification.created_at', 'DESC')
        .take(query.limit + 1);

      if (query.isRead !== undefined) {
        qb.andWhere('notification.is_read = :isRead', { isRead: query.isRead });
      }

      if (query.cursor) {
        qb.andWhere('notification.created_at < :cursor', { cursor: new Date(query.cursor) });
      }

      const notifications = await qb.getMany();

      const hasMore = notifications.length > query.limit;
      const items = hasMore ? notifications.slice(0, query.limit) : notifications;
      const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

      const unreadCount = await notificationRepo.count({
        where: { userId, isRead: false },
      });

      return reply.send({
        success: true,
        data: items,
        meta: { cursor: nextCursor, hasMore, unreadCount },
      });
    },
  );

  // ─── PATCH /notifications/read-all ───
  fastify.patch(
    '/notifications/read-all',
    {
      onRequest: [fastify.authenticate],
      schema: { tags: ['Notifications'], summary: '전체 읽음 처리', security: [{ bearerAuth: [] }] },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      await notificationRepo.update(
        { userId: request.user.userId, isRead: false },
        { isRead: true },
      );
      return reply.send({ success: true, data: { message: '모든 알림이 읽음 처리되었습니다.' } });
    },
  );

  // ─── PATCH /notifications/:id/read ───
  fastify.patch(
    '/notifications/:id/read',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Notifications'],
        summary: '단건 읽음 처리',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      await notificationRepo.update(
        { id: request.params.id, userId: request.user.userId },
        { isRead: true },
      );
      return reply.send({ success: true, data: { message: '알림이 읽음 처리되었습니다.' } });
    },
  );

  // ─── POST /devices/push-token ───
  fastify.post(
    '/devices/push-token',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Notifications'],
        summary: '푸시 토큰 등록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: RegisterPushTokenDto }>, reply: FastifyReply) => {
      const dto = registerPushTokenSchema.parse(request.body);
      const userId = request.user.userId;

      // upsert: token이 이미 존재하면 update, 없으면 insert
      const existing = await deviceTokenRepo.findOne({ where: { token: dto.token } });

      if (existing) {
        await deviceTokenRepo.update(
          { token: dto.token },
          { userId, isActive: true, updatedAt: new Date() },
        );
      } else {
        const newToken = deviceTokenRepo.create({
          userId,
          token: dto.token,
          platform: dto.platform as DevicePlatform,
          isActive: true,
        });
        await deviceTokenRepo.save(newToken);
      }

      return reply.status(201).send({ success: true, data: { message: '푸시 토큰이 등록되었습니다.' } });
    },
  );

  // ─── DELETE /devices/push-token ───
  fastify.delete(
    '/devices/push-token',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Notifications'],
        summary: '푸시 토큰 해제',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest<{ Body: DeletePushTokenDto }>, reply: FastifyReply) => {
      const dto = deletePushTokenSchema.parse(request.body);

      await deviceTokenRepo.update(
        { userId: request.user.userId, token: dto.token },
        { isActive: false },
      );

      return reply.send({ success: true, data: { message: '푸시 토큰이 해제되었습니다.' } });
    },
  );

  // ─── PATCH /notifications/settings ───
  fastify.patch(
    '/notifications/settings',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Notifications'],
        summary: '알림 설정 변경',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: UpdateNotificationSettingsDto }>,
      reply: FastifyReply,
    ) => {
      const dto = updateNotificationSettingsSchema.parse(request.body);
      const userId = request.user.userId;

      const updateData: Partial<NotificationSettings> = {};
      if (dto.chatMessage !== undefined) updateData.chatMessage = dto.chatMessage;
      if (dto.matchFound !== undefined) updateData.matchFound = dto.matchFound;
      if (dto.matchRequest !== undefined) updateData.matchRequest = dto.matchRequest;
      if (dto.gameResult !== undefined) updateData.gameResult = dto.gameResult;
      if (dto.scoreChange !== undefined) updateData.scoreChange = dto.scoreChange;
      if (dto.communityReply !== undefined) updateData.communityReply = dto.communityReply;

      // doNotDisturbStart/End는 time 타입 (HH:MM 문자열) 그대로 저장
      if (dto.doNotDisturbStart !== undefined) {
        updateData.doNotDisturbStart = dto.doNotDisturbStart ?? null;
      }
      if (dto.doNotDisturbEnd !== undefined) {
        updateData.doNotDisturbEnd = dto.doNotDisturbEnd ?? null;
      }

      // upsert: 기존 설정이 있으면 update, 없으면 insert
      const existing = await notificationSettingsRepo.findOne({ where: { userId } });

      if (existing) {
        await notificationSettingsRepo.update({ userId }, updateData as any);
      } else {
        const newSettings = notificationSettingsRepo.create({ userId, ...updateData });
        await notificationSettingsRepo.save(newSettings);
      }

      // 캐시 무효화
      await redis.del(`notif_settings:${userId}`);

      return reply.send({ success: true, data: { message: '알림 설정이 저장되었습니다.' } });
    },
  );
}
