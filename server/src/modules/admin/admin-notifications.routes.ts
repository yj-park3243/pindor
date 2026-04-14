import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Notification, User, UserPin } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';
import type { NotificationService } from '../notifications/notification.service.js';

export async function adminNotificationsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── POST /admin/notifications/send ── 알림 발송
  fastify.post(
    '/admin/notifications/send',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '어드민 알림 발송', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Body: {
          title: string;
          body: string;
          targetType: 'ALL' | 'SPORT' | 'PIN' | 'USER';
          targetId?: string;
          sportType?: string;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { title, body, targetType, targetId, sportType } = request.body;

      const notificationRepo = AppDataSource.getRepository(Notification);
      const userRepo = AppDataSource.getRepository(User);

      let targetUserIds: string[] = [];

      if (targetType === 'ALL') {
        // 활성 사용자 최대 1000명
        const users = await userRepo
          .createQueryBuilder('user')
          .select('user.id')
          .where('user.status = :status', { status: 'ACTIVE' })
          .take(1000)
          .getMany();
        targetUserIds = users.map((u) => u.id);
      } else if (targetType === 'USER') {
        if (!targetId) {
          throw AppError.badRequest(ErrorCode.BAD_REQUEST, 'USER 타입은 targetId가 필요합니다.');
        }
        const user = await userRepo.findOne({ where: { id: targetId } });
        if (!user) {
          throw AppError.notFound(ErrorCode.USER_NOT_FOUND, '사용자를 찾을 수 없습니다.');
        }
        targetUserIds = [targetId];
      } else if (targetType === 'SPORT') {
        if (!sportType) {
          throw AppError.badRequest(ErrorCode.BAD_REQUEST, 'SPORT 타입은 sportType이 필요합니다.');
        }
        // 해당 종목 스포츠 프로필을 가진 사용자
        const users = await userRepo
          .createQueryBuilder('user')
          .select('user.id')
          .innerJoin('user.sportsProfiles', 'sp', 'sp.sportType = :sportType AND sp.isActive = true', {
            sportType,
          })
          .where('user.status = :status', { status: 'ACTIVE' })
          .getMany();
        targetUserIds = users.map((u) => u.id);
      } else if (targetType === 'PIN') {
        if (!targetId) {
          throw AppError.badRequest(ErrorCode.BAD_REQUEST, 'PIN 타입은 targetId(pinId)가 필요합니다.');
        }
        // 해당 핀에 소속된 사용자
        const userPinRepo = AppDataSource.getRepository(UserPin);
        const userPins = await userPinRepo
          .createQueryBuilder('up')
          .select('up.userId')
          .where('up.pinId = :pinId', { pinId: targetId })
          .getMany();
        targetUserIds = userPins.map((up) => up.userId);
      }

      if (targetUserIds.length === 0) {
        return reply.send({ success: true, data: { sentCount: 0 } });
      }

      // NotificationService를 통해 실제 푸시 알림 발송 (DB 저장 + Socket.io + FCM)
      const notificationSvc = (global as any).__notificationService as NotificationService | undefined;

      if (notificationSvc) {
        // NotificationService.send()는 DB 저장 + Socket + FCM 푸시를 모두 처리
        // 대량 발송 시 병렬 처리 (10건씩 배치)
        const batchSize = 10;
        for (let i = 0; i < targetUserIds.length; i += batchSize) {
          const batch = targetUserIds.slice(i, i + batchSize);
          await Promise.allSettled(
            batch.map((userId) =>
              notificationSvc.send({
                userId,
                type: 'ADMIN' as any,
                title,
                body,
                data: { adminSent: 'true' },
              }),
            ),
          );
        }
      } else {
        // fallback: NotificationService 미초기화 시 DB에만 저장
        const notifications = targetUserIds.map((userId) =>
          notificationRepo.create({
            userId,
            type: 'ADMIN',
            title,
            body,
            data: { adminSent: true },
          }),
        );
        await notificationRepo.save(notifications, { chunk: 200 });
      }

      return reply.send({ success: true, data: { sentCount: targetUserIds.length } });
    },
  );

  // ─── GET /admin/notifications/logs ── 어드민 발송 알림 로그
  fastify.get(
    '/admin/notifications/logs',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '어드민 알림 발송 로그', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { page?: number; pageSize?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { page, pageSize, skip } = parsePageParams(request.query);

      const notificationRepo = AppDataSource.getRepository(Notification);
      const qb = notificationRepo
        .createQueryBuilder('notification')
        .leftJoinAndSelect('notification.user', 'user')
        .where('notification.type = :type', { type: 'ADMIN' });

      const [items, total] = await qb
        .orderBy('notification.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );
}
