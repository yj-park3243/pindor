import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, SportType, Tier, RankingEntry, SportsProfile } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

export async function adminRankingsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/rankings ── 랭킹 목록
  fastify.get(
    '/admin/rankings',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '랭킹 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { sportType?: string; tier?: string; page?: number; pageSize?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { sportType, tier } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const rankingRepo = AppDataSource.getRepository(RankingEntry);
      const qb = rankingRepo
        .createQueryBuilder('rankingEntry')
        .leftJoinAndSelect('rankingEntry.sportsProfile', 'sportsProfile')
        .leftJoinAndSelect('sportsProfile.user', 'user')
        .leftJoinAndSelect('rankingEntry.pin', 'pin');

      if (sportType) {
        qb.andWhere('rankingEntry.sportType = :sportType', { sportType });
      }
      if (tier) {
        qb.andWhere('rankingEntry.tier = :tier', { tier });
      }

      const [items, total] = await qb
        .orderBy('rankingEntry.updatedAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/rankings/pins/:pinId ── 특정 핀의 랭킹 목록
  // 주의: /anomalies 보다 앞에 등록되어야 하지만, 실제로는 /pins/:pinId 이므로 충돌 없음
  fastify.get(
    '/admin/rankings/pins/:pinId',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '핀별 랭킹 목록',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { pinId: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { pinId: string };
        Querystring: { sportType?: string; page?: number; pageSize?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { pinId } = request.params;
      const { sportType } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      const rankingRepo = AppDataSource.getRepository(RankingEntry);
      const qb = rankingRepo
        .createQueryBuilder('rankingEntry')
        .leftJoinAndSelect('rankingEntry.sportsProfile', 'sportsProfile')
        .leftJoinAndSelect('sportsProfile.user', 'user')
        .where('rankingEntry.pinId = :pinId', { pinId });

      if (sportType) {
        qb.andWhere('rankingEntry.sportType = :sportType', { sportType });
      }

      const [items, total] = await qb
        .orderBy('rankingEntry.rank', 'ASC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/rankings/anomalies ── 이상 랭킹 목록 (anomalies 먼저 등록)
  fastify.get(
    '/admin/rankings/anomalies',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: { tags: ['Admin'], summary: '이상 랭킹 목록', security: [{ bearerAuth: [] }] },
    },
    async (
      request: FastifyRequest<{
        Querystring: { isResolved?: string; page?: number; pageSize?: number };
      }>,
      reply: FastifyReply,
    ) => {
      const { page, pageSize, skip } = parsePageParams(request.query);

      const rankingRepo = AppDataSource.getRepository(RankingEntry);
      const qb = rankingRepo
        .createQueryBuilder('rankingEntry')
        .leftJoinAndSelect('rankingEntry.sportsProfile', 'sportsProfile')
        .leftJoinAndSelect('sportsProfile.user', 'user')
        .leftJoinAndSelect('rankingEntry.pin', 'pin')
        .where(
          '(rankingEntry.score > 2000 OR rankingEntry.score < 500 OR (rankingEntry.gamesPlayed = 0 AND rankingEntry.score != 1000))',
        );

      const [rawEntries, total] = await qb
        .orderBy('rankingEntry.updatedAt', 'DESC')
        .skip(skip)
        .take(pageSize)
        .getManyAndCount();

      // 이상 사유 계산
      const items = rawEntries.map((entry) => {
        const reasons: string[] = [];
        if (entry.score > 2000) reasons.push('점수 상한 초과 (>2000)');
        if (entry.score < 500) reasons.push('점수 하한 미달 (<500)');
        if (entry.gamesPlayed === 0 && entry.score !== 1000)
          reasons.push('경기 없이 초기값 변조 (gamesPlayed=0, score!=1000)');
        return {
          ...entry,
          isResolved: false,
          reason: reasons.join('; '),
        };
      });

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── PATCH /admin/rankings/anomalies/:id/resolve ── 이상 랭킹 확인 처리
  fastify.patch(
    '/admin/rankings/anomalies/:id/resolve',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '이상 랭킹 확인 처리',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { note: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { note } = request.body ?? {};

      // 전용 이상 테이블이 없으므로 랭킹 엔트리 존재 여부만 확인 후 acknowledge
      const rankingRepo = AppDataSource.getRepository(RankingEntry);
      const entry = await rankingRepo.findOne({ where: { id } });
      if (!entry) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '랭킹 엔트리를 찾을 수 없습니다.');
      }

      return reply.send({
        success: true,
        data: { id, resolved: true, note: note ?? '' },
      });
    },
  );

  // ─── POST /admin/rankings/season-reset ── 시즌 초기화
  fastify.post(
    '/admin/rankings/season-reset',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '시즌 초기화 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{ Body: { sportType: string } }>,
      reply: FastifyReply,
    ) => {
      const { sportType } = request.body ?? {};

      if (!sportType) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'sportType은 필수입니다.' },
        });
      }

      // sportType 유효성 검증
      const validSportTypes = Object.values(SportType) as string[];
      if (!validSportTypes.includes(sportType)) {
        return reply.status(400).send({
          success: false,
          error: {
            code: 'VALIDATION_ERROR',
            message: `유효하지 않은 sportType입니다. 가능한 값: ${validSportTypes.join(', ')}`,
          },
        });
      }

      await AppDataSource.transaction(async (manager) => {
        // SportsProfile 초기화: currentScore=1000, tier=BRONZE, 통계 0으로 리셋
        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({
            currentScore: 1000,
            tier: Tier.BRONZE,
            gamesPlayed: 0,
            wins: 0,
            losses: 0,
            draws: 0,
          })
          .where('sportType = :sportType', { sportType })
          .execute();

        // RankingEntry 삭제
        await manager
          .createQueryBuilder()
          .delete()
          .from(RankingEntry)
          .where('sportType = :sportType', { sportType })
          .execute();
      });

      return reply.send({
        success: true,
        data: { message: '시즌이 초기화되었습니다.', sportType },
      });
    },
  );
}
