import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Match, MatchStatus, Message, ChatRoom, Report } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminMatchesRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/matches ───
  fastify.get(
    '/admin/matches',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '매치 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          status?: string;
          sportType?: string;
          search?: string;
          page?: number;
          pageSize?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { status, sportType, search } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const matchRepo = AppDataSource.getRepository(Match);
      const qb = matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser');

      if (status) {
        qb.andWhere('match.status = :status', { status: status as MatchStatus });
      }
      if (sportType) {
        qb.andWhere('match.sportType = :sportType', { sportType });
      }
      if (search) {
        qb.andWhere(
          '(requesterUser.nickname ILIKE :search OR opponentUser.nickname ILIKE :search)',
          { search: `%${search}%` },
        );
      }

      const [items, total] = await qb
        .orderBy('match.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/matches/:id ───
  fastify.get(
    '/admin/matches/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '매치 상세 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('match.id = :id', { id: request.params.id })
        .getOne();

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      return reply.send({ success: true, data: match });
    },
  );

  // ─── PATCH /admin/matches/:id/force-cancel ───
  fastify.patch(
    '/admin/matches/:id/force-cancel',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '매치 강제 취소',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['reason'],
          properties: { reason: { type: 'string', minLength: 1 } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { reason } = request.body;

      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo.findOne({ where: { id } });

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      await matchRepo.update(id, {
        status: MatchStatus.CANCELLED,
        cancelReason: reason,
        cancelledBy: request.user.userId,
      });

      const updatedMatch = await matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('match.id = :id', { id })
        .getOne();

      return reply.send({ success: true, data: updatedMatch });
    },
  );

  // ─── PATCH /admin/matches/:id/force-complete ───
  fastify.patch(
    '/admin/matches/:id/force-complete',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '매치 강제 완료',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo.findOne({ where: { id } });

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      await matchRepo.update(id, {
        status: MatchStatus.COMPLETED,
        completedAt: new Date(),
      });

      const updatedMatch = await matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where('match.id = :id', { id })
        .getOne();

      return reply.send({ success: true, data: updatedMatch });
    },
  );

  // ─── GET /admin/matches/:id/messages — 매칭 채팅방 메시지 조회 ───
  fastify.get(
    '/admin/matches/:id/messages',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '매칭 채팅방 메시지 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const matchRepo = AppDataSource.getRepository(Match);
      const match = await matchRepo.findOne({ where: { id: request.params.id } });

      if (!match) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '매치를 찾을 수 없습니다.');
      }

      if (!match.chatRoomId) {
        return reply.send({ success: true, data: [] });
      }

      const msgRepo = AppDataSource.getRepository(Message);
      const messages = await msgRepo
        .createQueryBuilder('msg')
        .leftJoinAndSelect('msg.sender', 'sender')
        .where('msg.chatRoomId = :roomId', { roomId: match.chatRoomId })
        .orderBy('msg.createdAt', 'ASC')
        .getMany();

      const items = messages.map((m) => ({
        id: m.id,
        senderId: m.senderId,
        senderNickname: m.sender?.nickname ?? '',
        senderProfileImageUrl: (m.sender as any)?.profileImageUrl ?? null,
        messageType: m.messageType,
        content: m.content,
        imageUrl: m.imageUrl,
        extraData: m.extraData,
        createdAt: m.createdAt,
      }));

      return reply.send({ success: true, data: items });
    },
  );

  // ─── GET /admin/noshow-reports — 노쇼 신고 목록 ───
  fastify.get(
    '/admin/noshow-reports',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '노쇼 신고 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{
        Querystring: { status?: string; search?: string; page?: number; pageSize?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { status, search } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const reportRepo = AppDataSource.getRepository(Report);
      const qb = reportRepo
        .createQueryBuilder('report')
        .leftJoinAndSelect('report.reporter', 'reporter')
        .where("report.reason = 'NOSHOW'");

      if (status) {
        qb.andWhere('report.status = :status', { status });
      }
      if (search) {
        qb.andWhere('reporter.nickname ILIKE :search', { search: `%${search}%` });
      }

      const [reports, total] = await qb
        .orderBy('report.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      // 노쇼 신고의 targetId = noshowUserId, description에 matchId 포함
      // description 형식: "매치 {matchId} 노쇼 신고"
      const items = await Promise.all(
        reports.map(async (r) => {
          // targetId로 노쇼 당한 유저 조회
          const targetUser = await AppDataSource.query(
            `SELECT id, nickname, profile_image_url as "profileImageUrl" FROM users WHERE id = $1`,
            [r.targetId],
          );

          // description에서 matchId 추출
          const matchIdMatch = r.description?.match(/매치\s+([0-9a-f-]+)/i);
          const matchId = matchIdMatch?.[1] ?? null;

          let matchInfo = null;
          if (matchId) {
            const matchRepo = AppDataSource.getRepository(Match);
            const match = await matchRepo
              .createQueryBuilder('match')
              .leftJoinAndSelect('match.requesterProfile', 'rp')
              .leftJoinAndSelect('rp.user', 'ru')
              .leftJoinAndSelect('match.opponentProfile', 'op')
              .leftJoinAndSelect('op.user', 'ou')
              .where('match.id = :matchId', { matchId })
              .getOne();
            if (match) {
              matchInfo = {
                id: match.id,
                sportType: match.sportType,
                status: match.status,
                chatRoomId: match.chatRoomId,
                requesterNickname: match.requesterProfile?.user?.nickname ?? '',
                opponentNickname: match.opponentProfile?.user?.nickname ?? '',
                scheduledDate: match.scheduledDate,
                createdAt: match.createdAt,
              };
            }
          }

          return {
            id: r.id,
            reporterId: r.reporterId,
            reporterNickname: r.reporter?.nickname ?? '',
            targetId: r.targetId,
            targetNickname: targetUser[0]?.nickname ?? '',
            targetProfileImageUrl: targetUser[0]?.profileImageUrl ?? null,
            description: r.description,
            imageUrls: r.imageUrls,
            status: r.status,
            resolvedBy: r.resolvedBy,
            resolvedAt: r.resolvedAt,
            createdAt: r.createdAt,
            match: matchInfo,
          };
        }),
      );

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );
}
