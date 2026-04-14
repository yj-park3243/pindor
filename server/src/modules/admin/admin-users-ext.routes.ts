import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AppDataSource } from '../../config/database.js';
import {
  User,
  SportsProfile,
  Match,
  Game,
  AdminRole,
  UserStatus,
} from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminUsersExtRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/users/:id ── 사용자 상세 조회
  fastify.get(
    '/admin/users/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 상세 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({
        where: { id: request.params.id },
        relations: { sportsProfiles: true },
      });

      if (!user) {
        throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
      }

      return reply.send({ success: true, data: user });
    },
  );

  // ─── PATCH /admin/users/:id/unsuspend ── 사용자 정지 해제
  fastify.patch(
    '/admin/users/:id/unsuspend',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 정지 해제',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({ where: { id: request.params.id } });

      if (!user) {
        throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
      }

      await userRepo.update(request.params.id, { status: UserStatus.ACTIVE });

      const updated = await userRepo.findOne({ where: { id: request.params.id } });
      return reply.send({ success: true, data: updated });
    },
  );

  // ─── PATCH /admin/users/:id/status ── 사용자 상태 변경 (ADMIN 이상)
  fastify.patch(
    '/admin/users/:id/status',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 상태 변경',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { status: UserStatus; reason?: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { status } = request.body as { status: UserStatus; reason?: string };

      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({ where: { id: request.params.id } });

      if (!user) {
        throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
      }

      await userRepo.update(request.params.id, { status });

      const updated = await userRepo.findOne({ where: { id: request.params.id } });
      return reply.send({ success: true, data: updated });
    },
  );

  // ─── DELETE /admin/users/:id ── 사용자 삭제 (소프트 삭제, SUPER_ADMIN 전용)
  fastify.delete(
    '/admin/users/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 삭제 (소프트)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({ where: { id: request.params.id } });

      if (!user) {
        throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
      }

      await userRepo.update(request.params.id, { status: UserStatus.WITHDRAWN });

      return reply.send({ success: true, data: { message: '사용자가 탈퇴 처리되었습니다.' } });
    },
  );

  // ─── GET /admin/users/:id/games ── 사용자의 경기 목록
  fastify.get(
    '/admin/users/:id/games',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 경기 목록',
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
      const { id } = request.params;
      const { page, pageSize, skip } = parsePageParams(request.query);

      // 유저 존재 확인
      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({ where: { id } });
      if (!user) {
        throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
      }

      // 해당 유저의 스포츠 프로필 ID 목록 조회
      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const profiles = await profileRepo.find({ where: { userId: id } });
      const profileIds = profiles.map((p) => p.id);

      if (profileIds.length === 0) {
        return reply.send({ success: true, data: paginatedResponse([], 0, page, pageSize) });
      }

      const gameRepo = AppDataSource.getRepository(Game);
      const qb = gameRepo
        .createQueryBuilder('game')
        .leftJoinAndSelect('game.match', 'match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .where(
          '(match.requesterProfileId IN (:...profileIds) OR match.opponentProfileId IN (:...profileIds))',
          { profileIds },
        );

      const [items, total] = await qb
        .orderBy('game.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/users/:id/matches ── 사용자의 매칭 목록
  fastify.get(
    '/admin/users/:id/matches',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '사용자 매칭 목록',
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
      const { id } = request.params;
      const { page, pageSize, skip } = parsePageParams(request.query);

      // 유저 존재 확인
      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({ where: { id } });
      if (!user) {
        throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
      }

      // 해당 유저의 스포츠 프로필 ID 목록 조회
      const profileRepo = AppDataSource.getRepository(SportsProfile);
      const profiles = await profileRepo.find({ where: { userId: id } });
      const profileIds = profiles.map((p) => p.id);

      if (profileIds.length === 0) {
        return reply.send({ success: true, data: paginatedResponse([], 0, page, pageSize) });
      }

      const matchRepo = AppDataSource.getRepository(Match);
      const qb = matchRepo
        .createQueryBuilder('match')
        .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
        .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
        .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
        .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
        .where(
          '(match.requesterProfileId IN (:...profileIds) OR match.opponentProfileId IN (:...profileIds))',
          { profileIds },
        );

      const [items, total] = await qb
        .orderBy('match.createdAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );
}
