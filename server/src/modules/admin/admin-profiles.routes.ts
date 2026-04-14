import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import {
  SportsProfile,
  ScoreHistory,
  AdminRole,
  SportType,
  Tier,
  ScoreChangeType,
} from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { calculateTier } from '../../shared/utils/elo.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminProfilesRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/sports-profiles ── 스포츠 프로필 목록
  fastify.get(
    '/admin/sports-profiles',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '스포츠 프로필 목록',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          search?: string;
          sportType?: string;
          tier?: string;
          page?: number;
          pageSize?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { search, sportType, tier } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const qb = profileRepo
        .createQueryBuilder('profile')
        .leftJoinAndSelect('profile.user', 'user');

      if (sportType) {
        qb.andWhere('profile.sportType = :sportType', { sportType: sportType as SportType });
      }
      if (tier) {
        qb.andWhere('profile.tier = :tier', { tier: tier as Tier });
      }
      if (search) {
        qb.andWhere('user.nickname ILIKE :search', { search: `%${search}%` });
      }

      const [items, total] = await qb
        .orderBy('profile.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/sports-profiles/:id ── 스포츠 프로필 상세
  fastify.get(
    '/admin/sports-profiles/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '스포츠 프로필 상세',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const profile = await profileRepo.findOne({
        where: { id: request.params.id },
        relations: { user: true },
      });

      if (!profile) {
        throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
      }

      return reply.send({ success: true, data: profile });
    },
  );

  // ─── POST /admin/sports-profiles/:id/score-adjust ── 점수 수동 조정 (ADMIN 이상)
  fastify.post(
    '/admin/sports-profiles/:id/score-adjust',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '스포츠 프로필 점수 수동 조정',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { adjustment: number; reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { adjustment, reason } = request.body as { adjustment: number; reason: string };

      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const profile = await profileRepo.findOne({ where: { id: request.params.id } });

      if (!profile) {
        throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
      }

      const scoreBefore = profile.currentScore;
      const newScore = Math.max(100, scoreBefore + adjustment);
      const newTier = calculateTier(newScore);

      await AppDataSource.transaction(async (manager) => {
        // 점수 및 티어 업데이트
        await manager.getRepository(SportsProfile).update(request.params.id, {
          currentScore: newScore,
          tier: newTier,
        });

        // 점수 이력 생성
        const historyRepo = manager.getRepository(ScoreHistory);
        const entry = historyRepo.create({
          sportsProfileId: request.params.id,
          gameId: null,
          changeType: ScoreChangeType.ADMIN_ADJUST,
          scoreBefore,
          scoreChange: adjustment,
          scoreAfter: newScore,
          opponentScore: null,
          kFactor: null,
        });
        await historyRepo.save(entry);
      });

      const updated = await profileRepo.findOne({
        where: { id: request.params.id },
        relations: { user: true },
      });

      return reply.send({ success: true, data: updated });
    },
  );

  // ─── GET /admin/sports-profiles/:id/score-history ── 점수 이력 조회
  fastify.get(
    '/admin/sports-profiles/:id/score-history',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '스포츠 프로필 점수 이력',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Querystring: { page?: number; pageSize?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { page, pageSize, skip } = parsePageParams(request.query);

      // 프로필 존재 확인
      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const profile = await profileRepo.findOne({ where: { id: request.params.id } });
      if (!profile) {
        throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
      }

      const historyRepo = AppDataSource.getRepository(ScoreHistory);
      const qb = historyRepo
        .createQueryBuilder('history')
        .where('history.sportsProfileId = :profileId', { profileId: request.params.id });

      const [items, total] = await qb
        .orderBy('history.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── PATCH /admin/sports-profiles/:id/verify ── 프로필 인증 상태 변경 (ADMIN 이상)
  fastify.patch(
    '/admin/sports-profiles/:id/verify',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '스포츠 프로필 인증 상태 변경',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { isVerified: boolean };
      }>,
      reply: FastifyReply,
    ) => {
      const { isVerified } = request.body as { isVerified: boolean };

      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const profile = await profileRepo.findOne({ where: { id: request.params.id } });

      if (!profile) {
        throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
      }

      await profileRepo.update(request.params.id, { isVerified });

      const updated = await profileRepo.findOne({
        where: { id: request.params.id },
        relations: { user: true },
      });

      return reply.send({ success: true, data: updated });
    },
  );
}
