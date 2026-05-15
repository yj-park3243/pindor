import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { AppDataSource } from '../../config/database.js';
import { AdminRole, Dispute, Game, Match, User } from '../../entities/index.js';
import { requireAdmin } from '../admin/admin.middleware.js';
import { sendAdminAlert, escapeHtml } from '../../shared/services/telegram.service.js';

// ─── 입력 스키마 ───

const createDisputeSchema = z.object({
  matchId: z.string().uuid('올바른 매칭 ID가 아닙니다.'),
  title: z.string().min(1, '제목을 입력해주세요.').max(200, '제목은 200자 이하로 입력해주세요.'),
  content: z.string().min(1, '내용을 입력해주세요.'),
  imageUrls: z.array(z.string().url()).max(3).optional(),
  phoneNumber: z.string().max(20).optional(),
});

const listDisputesQuerySchema = z.object({
  page: z.coerce.number().min(1).default(1),
  pageSize: z.coerce.number().min(1).max(50).default(20),
});

const adminListDisputesQuerySchema = z.object({
  status: z.enum(['PENDING', 'IN_PROGRESS', 'RESOLVED']).optional(),
  page: z.coerce.number().min(1).default(1),
  pageSize: z.coerce.number().min(1).max(50).default(20),
});

const adminUpdateDisputeSchema = z.object({
  status: z.enum(['IN_PROGRESS', 'RESOLVED']),
  adminReply: z.string().optional(),
  // RESOLVED 시점에 게임 결과까지 확정할 때 사용.
  // action:
  //  - 'KEEP_ORIGINAL'  — 게임 원래 결과 유지 + VERIFIED
  //  - 'MODIFY_RESULT'  — 관리자가 승자 지정 + VERIFIED (winnerProfileId 필수)
  //  - 'VOID_GAME'      — 게임 무효 처리 (VOIDED + 매칭 CANCELLED)
  resolution: z
    .object({
      action: z.enum(['KEEP_ORIGINAL', 'MODIFY_RESULT', 'VOID_GAME']),
      winnerProfileId: z.string().uuid().optional(),
      requesterScore: z.number().int().min(0).optional(),
      opponentScore: z.number().int().min(0).optional(),
    })
    .optional(),
});

type CreateDisputeDto = z.infer<typeof createDisputeSchema>;
type AdminUpdateDisputeDto = z.infer<typeof adminUpdateDisputeSchema>;

export async function disputesRoutes(fastify: FastifyInstance): Promise<void> {
  const disputeRepo = AppDataSource.getRepository(Dispute);
  const matchRepo = AppDataSource.getRepository(Match);

  // ─── POST /disputes — 이의 제기 접수 ───
  fastify.post(
    '/disputes',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Disputes'],
        summary: '이의 제기 접수',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const dto = createDisputeSchema.parse(request.body);
      const reporterId = request.user.userId;

      // 매칭 존재 여부 확인
      const match = await matchRepo.findOne({ where: { id: dto.matchId } });
      if (!match) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '매칭을 찾을 수 없습니다.' },
        });
      }

      const dispute = disputeRepo.create({
        matchId: dto.matchId,
        reporterId,
        title: dto.title,
        content: dto.content,
        imageUrls: dto.imageUrls ?? [],
        phoneNumber: dto.phoneNumber ?? null,
        status: 'PENDING',
        adminReply: null,
        resolvedBy: null,
      });

      await disputeRepo.save(dispute);

      // 텔레그램 관리자 알림
      try {
        const userRepo = AppDataSource.getRepository(User);
        const u = await userRepo.findOne({ where: { id: reporterId } });
        void sendAdminAlert(
          `⚖️ <b>이의제기 접수</b>\n` +
            `• 닉네임: ${escapeHtml(u?.nickname ?? reporterId)}\n` +
            `• 매칭 ID: <code>${escapeHtml(dto.matchId)}</code>\n` +
            `• 제목: ${escapeHtml(dto.title)}\n` +
            `• 내용: ${escapeHtml(dto.content.slice(0, 500))}`,
        );
      } catch (_) {}

      return reply.status(201).send({
        success: true,
        data: { id: dispute.id, message: '이의 제기가 접수되었습니다.' },
      });
    },
  );

  // ─── GET /disputes — 내 이의 제기 목록 ───
  fastify.get(
    '/disputes',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Disputes'],
        summary: '내 이의 제기 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userId = request.user.userId;
      const query = listDisputesQuerySchema.parse(request.query);
      const { page, pageSize } = query;

      const [items, total] = await disputeRepo.findAndCount({
        where: { reporterId: userId },
        order: { createdAt: 'DESC' },
        skip: (page - 1) * pageSize,
        take: pageSize,
        select: {
          id: true,
          matchId: true,
          title: true,
          status: true,
          adminReply: true,
          createdAt: true,
          updatedAt: true,
        } as any,
      });

      return reply.send({
        success: true,
        data: items,
        meta: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    },
  );

  // ─── GET /disputes/:id — 이의 제기 상세 ───
  fastify.get(
    '/disputes/:id',
    {
      onRequest: [fastify.authenticate],
      schema: {
        tags: ['Disputes'],
        summary: '이의 제기 상세',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const userId = request.user.userId;
      const { id } = request.params as { id: string };

      const dispute = await disputeRepo.findOne({
        where: { id, reporterId: userId },
      });

      if (!dispute) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '이의 제기를 찾을 수 없습니다.' },
        });
      }

      return reply.send({ success: true, data: dispute });
    },
  );

  // ─── GET /admin/disputes — 어드민: 전체 이의 제기 목록 ───
  fastify.get(
    '/admin/disputes',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Disputes'],
        summary: '[어드민] 이의 제기 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const query = adminListDisputesQuerySchema.parse(request.query);
      const { status, page, pageSize } = query as any;

      const qb = disputeRepo
        .createQueryBuilder('d')
        .leftJoin('d.reporter', 'reporter')
        .addSelect(['reporter.id', 'reporter.nickname', 'reporter.email'])
        .orderBy('d.createdAt', 'DESC')
        .skip((page - 1) * pageSize)
        .take(pageSize);

      if (status) {
        qb.where('d.status = :status', { status });
      }

      const [rawItems, total] = await qb.getManyAndCount();

      // 매칭/게임/상대방 정보를 배치 조회하여 붙임
      const matchIds = Array.from(
        new Set(rawItems.map((d) => d.matchId).filter(Boolean)),
      );
      const matchRows = matchIds.length
        ? await AppDataSource.query(
            `
          SELECT
            m.id AS "matchId",
            m.sport_type AS "sportType",
            m.status AS "matchStatus",
            rp.id AS "requesterProfileId",
            rp.user_id AS "requesterUserId",
            ru.nickname AS "requesterNickname",
            op.id AS "opponentProfileId",
            op.user_id AS "opponentUserId",
            ou.nickname AS "opponentNickname",
            g.id AS "gameId",
            g.result_status AS "gameResultStatus",
            g.winner_profile_id AS "winnerProfileId",
            g.requester_score AS "requesterScore",
            g.opponent_score AS "opponentScore",
            g.requester_claimed_result AS "requesterClaimed",
            g.opponent_claimed_result AS "opponentClaimed"
          FROM matches m
          LEFT JOIN sports_profiles rp ON rp.id = m.requester_profile_id
          LEFT JOIN users ru ON ru.id = rp.user_id
          LEFT JOIN sports_profiles op ON op.id = m.opponent_profile_id
          LEFT JOIN users ou ON ou.id = op.user_id
          LEFT JOIN games g ON g.match_id = m.id
          WHERE m.id = ANY($1::uuid[])
          `,
            [matchIds],
          )
        : [];

      const matchMap = new Map<string, any>(
        matchRows.map((row: any) => [row.matchId, row]),
      );

      const items = rawItems.map((d: any) => {
        const mi = matchMap.get(d.matchId);
        return {
          ...d,
          match: mi
            ? {
                id: mi.matchId,
                sportType: mi.sportType,
                status: mi.matchStatus,
                requester: {
                  profileId: mi.requesterProfileId,
                  userId: mi.requesterUserId,
                  nickname: mi.requesterNickname,
                  claimedResult: mi.requesterClaimed,
                  score: mi.requesterScore,
                },
                opponent: {
                  profileId: mi.opponentProfileId,
                  userId: mi.opponentUserId,
                  nickname: mi.opponentNickname,
                  claimedResult: mi.opponentClaimed,
                  score: mi.opponentScore,
                },
                game: mi.gameId
                  ? {
                      id: mi.gameId,
                      resultStatus: mi.gameResultStatus,
                      winnerProfileId: mi.winnerProfileId,
                    }
                  : null,
              }
            : null,
        };
      });

      return reply.send({
        success: true,
        data: items,
        meta: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    },
  );

  // ─── PATCH /admin/disputes/:id — 어드민: 이의 제기 처리 ───
  fastify.patch(
    '/admin/disputes/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Disputes'],
        summary: '[어드민] 이의 제기 상태 업데이트',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: { id: { type: 'string', format: 'uuid' } },
          required: ['id'],
        },
      },
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const { id } = request.params as { id: string };
      const dto = adminUpdateDisputeSchema.parse(request.body);
      const adminId = request.user.userId;

      const dispute = await disputeRepo.findOne({ where: { id } });
      if (!dispute) {
        return reply.status(404).send({
          success: false,
          error: { code: 'NOT_FOUND', message: '이의 제기를 찾을 수 없습니다.' },
        });
      }

      // RESOLVED + resolution이 오면 게임 결과도 확정
      if (dto.status === 'RESOLVED' && dto.resolution) {
        const gameRepo = AppDataSource.getRepository(Game);
        const game = await gameRepo.findOne({ where: { matchId: dispute.matchId } });
        if (!game) {
          return reply.status(404).send({
            success: false,
            error: {
              code: 'GAME_NOT_FOUND',
              message: '대상 경기를 찾을 수 없습니다.',
            },
          });
        }

        if (dto.resolution.action === 'VOID_GAME') {
          await AppDataSource.transaction(async (manager) => {
            await manager
              .getRepository(Game)
              .update(game.id, { resultStatus: 'VOIDED' as any });
            await manager
              .getRepository(Match)
              .update(dispute.matchId, { status: 'CANCELLED' as any });
          });
        } else if (dto.resolution.action === 'MODIFY_RESULT') {
          if (!dto.resolution.winnerProfileId) {
            return reply.status(400).send({
              success: false,
              error: {
                code: 'BAD_REQUEST',
                message: 'MODIFY_RESULT 시 winnerProfileId가 필요합니다.',
              },
            });
          }
          await gameRepo.update(game.id, {
            resultStatus: 'VERIFIED' as any,
            winnerProfileId: dto.resolution.winnerProfileId,
            requesterScore: dto.resolution.requesterScore ?? null,
            opponentScore: dto.resolution.opponentScore ?? null,
            verifiedAt: new Date(),
          });
          await AppDataSource.getRepository(Match).update(dispute.matchId, {
            status: 'COMPLETED' as any,
            completedAt: new Date(),
          });
        } else {
          // KEEP_ORIGINAL — 게임 결과 유지 + VERIFIED
          await gameRepo.update(game.id, {
            resultStatus: 'VERIFIED' as any,
            verifiedAt: new Date(),
          });
          await AppDataSource.getRepository(Match).update(dispute.matchId, {
            status: 'COMPLETED' as any,
            completedAt: new Date(),
          });
        }
      }

      await disputeRepo.update(id, {
        status: dto.status,
        adminReply: dto.adminReply ?? dispute.adminReply,
        resolvedBy: dto.status === 'RESOLVED' ? adminId : dispute.resolvedBy,
      });

      const updated = await disputeRepo.findOne({ where: { id } });

      return reply.send({ success: true, data: updated });
    },
  );
}
