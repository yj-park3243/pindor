import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import {
  AdminRole,
  Team,
  TeamMember,
  TeamMatch,
  TeamPost,
  TeamStatus,
  TeamMemberStatus,
  SportType,
  MatchStatus,
} from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

export async function adminTeamsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/team-matches ── 팀 매치 목록 (반드시 /admin/teams/:id 보다 먼저 등록)
  fastify.get(
    '/admin/team-matches',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '팀 매치 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { status?: string; sportType?: string; cursor?: string; limit?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { status, sportType, cursor, limit = 20 } = request.query;

      const teamMatchRepo = AppDataSource.getRepository(TeamMatch);
      const qb = teamMatchRepo
        .createQueryBuilder('teamMatch')
        .leftJoinAndSelect('teamMatch.homeTeam', 'homeTeam')
        .leftJoinAndSelect('teamMatch.awayTeam', 'awayTeam');

      if (status) {
        qb.andWhere('teamMatch.status = :status', { status: status as MatchStatus });
      }
      if (sportType) {
        qb.andWhere('teamMatch.sportType = :sportType', { sportType: sportType as SportType });
      }
      if (cursor) {
        qb.andWhere('teamMatch.createdAt < :cursor', { cursor: new Date(cursor) });
      }

      const matches = await qb
        .orderBy('teamMatch.createdAt', 'DESC')
        .take(Number(limit) + 1)
        .getMany();

      const hasMore = matches.length > Number(limit);
      const items = hasMore ? matches.slice(0, Number(limit)) : matches;
      const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── GET /admin/teams ── 팀 목록
  fastify.get(
    '/admin/teams',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '팀 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: {
          search?: string;
          sportType?: string;
          status?: string;
          cursor?: string;
          limit?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { search, sportType, status, cursor, limit = 20 } = request.query;

      const teamRepo = AppDataSource.getRepository(Team);
      const qb = teamRepo.createQueryBuilder('team');

      if (search) {
        qb.andWhere('team.name ILIKE :search', { search: `%${search}%` });
      }
      if (sportType) {
        qb.andWhere('team.sportType = :sportType', { sportType: sportType as SportType });
      }
      if (status) {
        qb.andWhere('team.status = :status', { status: status as TeamStatus });
      }
      if (cursor) {
        qb.andWhere('team.createdAt < :cursor', { cursor: new Date(cursor) });
      }

      const teams = await qb
        .orderBy('team.createdAt', 'DESC')
        .take(Number(limit) + 1)
        .getMany();

      const hasMore = teams.length > Number(limit);
      const items = hasMore ? teams.slice(0, Number(limit)) : teams;
      const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

      return reply.send({ success: true, data: items, meta: { cursor: nextCursor, hasMore } });
    },
  );

  // ─── GET /admin/teams/:id ── 팀 상세
  fastify.get(
    '/admin/teams/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '팀 상세',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const teamRepo = AppDataSource.getRepository(Team);
      const team = await teamRepo.findOne({ where: { id: request.params.id } });

      if (!team) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '팀을 찾을 수 없습니다.');
      }

      return reply.send({ success: true, data: team });
    },
  );

  // ─── GET /admin/teams/:teamId/members ── 팀 멤버 목록
  fastify.get(
    '/admin/teams/:teamId/members',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '팀 멤버 목록',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { teamId: string } }>, reply: FastifyReply) => {
      const teamMemberRepo = AppDataSource.getRepository(TeamMember);
      const members = await teamMemberRepo
        .createQueryBuilder('teamMember')
        .leftJoinAndSelect('teamMember.user', 'user')
        .where('teamMember.teamId = :teamId', { teamId: request.params.teamId })
        .getMany();

      return reply.send({ success: true, data: members });
    },
  );

  // ─── GET /admin/teams/:teamId/matches ── 팀 매치 목록
  fastify.get(
    '/admin/teams/:teamId/matches',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '팀의 매치 목록',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { teamId: string } }>, reply: FastifyReply) => {
      const { teamId } = request.params;
      const teamMatchRepo = AppDataSource.getRepository(TeamMatch);

      const matches = await teamMatchRepo
        .createQueryBuilder('teamMatch')
        .leftJoinAndSelect('teamMatch.homeTeam', 'homeTeam')
        .leftJoinAndSelect('teamMatch.awayTeam', 'awayTeam')
        .where('teamMatch.homeTeamId = :teamId OR teamMatch.awayTeamId = :teamId', { teamId })
        .orderBy('teamMatch.createdAt', 'DESC')
        .take(50)
        .getMany();

      return reply.send({ success: true, data: matches });
    },
  );

  // ─── GET /admin/teams/:teamId/posts ── 팀 게시글 목록
  fastify.get(
    '/admin/teams/:teamId/posts',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '팀 게시글 목록',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { teamId: string } }>, reply: FastifyReply) => {
      const teamPostRepo = AppDataSource.getRepository(TeamPost);

      const posts = await teamPostRepo
        .createQueryBuilder('teamPost')
        .leftJoinAndSelect('teamPost.author', 'author')
        .where('teamPost.teamId = :teamId', { teamId: request.params.teamId })
        .orderBy('teamPost.createdAt', 'DESC')
        .take(50)
        .getMany();

      return reply.send({ success: true, data: posts });
    },
  );

  // ─── PATCH /admin/teams/:teamId/suspend ── 팀 정지
  fastify.patch(
    '/admin/teams/:teamId/suspend',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '팀 정지',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { teamId: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const teamRepo = AppDataSource.getRepository(Team);
      const team = await teamRepo.findOne({ where: { id: request.params.teamId } });

      if (!team) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '팀을 찾을 수 없습니다.');
      }

      await teamRepo.update(request.params.teamId, { status: TeamStatus.INACTIVE });

      return reply.send({ success: true, data: { message: '팀이 정지되었습니다.' } });
    },
  );

  // ─── PATCH /admin/teams/:teamId/activate ── 팀 활성화
  fastify.patch(
    '/admin/teams/:teamId/activate',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '팀 활성화',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { teamId: string } }>, reply: FastifyReply) => {
      const teamRepo = AppDataSource.getRepository(Team);
      const team = await teamRepo.findOne({ where: { id: request.params.teamId } });

      if (!team) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '팀을 찾을 수 없습니다.');
      }

      await teamRepo.update(request.params.teamId, { status: TeamStatus.ACTIVE });

      return reply.send({ success: true, data: { message: '팀이 활성화되었습니다.' } });
    },
  );

  // ─── PATCH /admin/teams/:teamId/disband ── 팀 해산
  fastify.patch(
    '/admin/teams/:teamId/disband',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '팀 해산',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { teamId: string }; Body: { reason: string } }>,
      reply: FastifyReply,
    ) => {
      const teamRepo = AppDataSource.getRepository(Team);
      const team = await teamRepo.findOne({ where: { id: request.params.teamId } });

      if (!team) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '팀을 찾을 수 없습니다.');
      }

      await teamRepo.update(request.params.teamId, { status: TeamStatus.DISBANDED });

      return reply.send({ success: true, data: { message: '팀이 해산되었습니다.' } });
    },
  );

  // ─── DELETE /admin/teams/:teamId/members/:userId ── 팀 멤버 강제 탈퇴(밴)
  fastify.delete(
    '/admin/teams/:teamId/members/:userId',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '팀 멤버 강제 탈퇴',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            teamId: { type: 'string', format: 'uuid' },
            userId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { teamId: string; userId: string };
        Body: { reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { teamId, userId } = request.params;

      await AppDataSource.transaction(async (manager) => {
        const teamMemberRepo = manager.getRepository(TeamMember);
        const member = await teamMemberRepo.findOne({ where: { teamId, userId } });

        if (!member) {
          throw AppError.notFound(ErrorCode.NOT_FOUND, '팀 멤버를 찾을 수 없습니다.');
        }

        await teamMemberRepo.update(member.id, { status: TeamMemberStatus.BANNED });

        const teamRepo = manager.getRepository(Team);
        await teamRepo
          .createQueryBuilder()
          .update(Team)
          .set({ currentMembers: () => 'current_members - 1' })
          .where('id = :teamId AND current_members > 0', { teamId })
          .execute();
      });

      return reply.send({ success: true, data: { message: '팀 멤버가 강제 탈퇴 처리되었습니다.' } });
    },
  );

  // ─── PATCH /admin/teams/:teamId/score ── 팀 점수 수정
  fastify.patch(
    '/admin/teams/:teamId/score',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '팀 점수 수정',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { teamId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { teamId: string };
        Body: { score: number; reason: string };
      }>,
      reply: FastifyReply,
    ) => {
      const { teamId } = request.params;
      const { score } = request.body as { score: number; reason: string };

      const teamRepo = AppDataSource.getRepository(Team);
      const team = await teamRepo.findOne({ where: { id: teamId } });

      if (!team) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '팀을 찾을 수 없습니다.');
      }

      await teamRepo.update(teamId, { teamScore: score });

      return reply.send({ success: true, data: { message: '팀 점수가 수정되었습니다.' } });
    },
  );

  // ─── DELETE /admin/teams/:teamId/posts/:postId ── 팀 게시글 삭제
  fastify.delete(
    '/admin/teams/:teamId/posts/:postId',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '팀 게시글 삭제',
        security: [{ bearerAuth: [] }],
        params: {
          type: 'object',
          properties: {
            teamId: { type: 'string', format: 'uuid' },
            postId: { type: 'string', format: 'uuid' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { teamId: string; postId: string } }>,
      reply: FastifyReply,
    ) => {
      const { teamId, postId } = request.params;

      const teamPostRepo = AppDataSource.getRepository(TeamPost);
      const post = await teamPostRepo.findOne({ where: { id: postId, teamId } });

      if (!post) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '게시글을 찾을 수 없습니다.');
      }

      await teamPostRepo.delete(postId);

      return reply.send({ success: true, data: { message: '게시글이 삭제되었습니다.' } });
    },
  );
}
