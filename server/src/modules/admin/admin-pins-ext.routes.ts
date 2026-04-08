import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, Pin, UserPin } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

/** 이름에서 슬러그 생성: 소문자 변환, 공백→하이픈, 랜덤 suffix 추가 */
function generateSlug(name: string): string {
  const base = name
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ-]/g, '')
    .slice(0, 80);
  const suffix = Math.random().toString(36).slice(2, 7);
  return `${base}-${suffix}`;
}

export async function adminPinsExtRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/pins/:id ── 핀 상세 조회
  // geography 컬럼(center) 직렬화 문제를 피하기 위해 특정 컬럼만 select + ST_Y/ST_X 사용
  fastify.get(
    '/admin/pins/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '핀 상세 조회',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      const result = await AppDataSource.query(
        `SELECT
           p.id,
           p.name,
           p.slug,
           p.level,
           p.parent_pin_id AS "parentPinId",
           p.region_code AS "regionCode",
           p.is_active AS "isActive",
           p.user_count AS "userCount",
           p.metadata,
           p.created_at AS "createdAt",
           ST_Y(p.center::geometry) AS "centerLat",
           ST_X(p.center::geometry) AS "centerLng"
         FROM pins p
         WHERE p.id = $1`,
        [id],
      );

      if (!result || result.length === 0) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '핀을 찾을 수 없습니다.');
      }

      return reply.send({ success: true, data: result[0] });
    },
  );

  // ─── GET /admin/pins/:id/stats ── 핀 통계
  fastify.get(
    '/admin/pins/:id/stats',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '핀 통계',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      // 핀 존재 여부 확인
      const pinRepo = AppDataSource.getRepository(Pin);
      const pin = await pinRepo.findOne({ where: { id } });
      if (!pin) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '핀을 찾을 수 없습니다.');
      }

      // 병렬로 통계 수집
      const [userCountResult, postCountResult, matchCountResult, rankingCountResult] =
        await Promise.all([
          AppDataSource.query(
            `SELECT COUNT(*)::int AS count FROM user_pins WHERE pin_id = $1`,
            [id],
          ),
          AppDataSource.query(
            `SELECT COUNT(*)::int AS count FROM posts WHERE pin_id = $1`,
            [id],
          ),
          AppDataSource.query(
            `SELECT COUNT(*)::int AS count FROM matches WHERE pin_id = $1`,
            [id],
          ),
          AppDataSource.query(
            `SELECT COUNT(*)::int AS count FROM ranking_entries WHERE pin_id = $1`,
            [id],
          ),
        ]);

      return reply.send({
        success: true,
        data: {
          pinId: id,
          userCount: userCountResult[0]?.count ?? 0,
          postCount: postCountResult[0]?.count ?? 0,
          matchCount: matchCountResult[0]?.count ?? 0,
          rankingCount: rankingCountResult[0]?.count ?? 0,
        },
      });
    },
  );

  // ─── POST /admin/pins ── 핀 생성
  fastify.post(
    '/admin/pins',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '핀 생성 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
      },
    },
    async (
      request: FastifyRequest<{
        Body: {
          name: string;
          center: { lat: number; lng: number };
          level: string;
          parentPinId?: string;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { name, center, level, parentPinId } = request.body ?? {};

      if (!name || !center || !level) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'name, center, level은 필수입니다.' },
        });
      }
      if (typeof center.lat !== 'number' || typeof center.lng !== 'number') {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'center.lat, center.lng는 숫자여야 합니다.' },
        });
      }

      const slug = generateSlug(name);

      const result = await AppDataSource.query(
        `INSERT INTO pins (name, slug, center, level, parent_pin_id, is_active)
         VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5, $6, true)
         RETURNING
           id, name, slug, level,
           parent_pin_id AS "parentPinId",
           region_code AS "regionCode",
           is_active AS "isActive",
           user_count AS "userCount",
           metadata,
           created_at AS "createdAt",
           ST_Y(center::geometry) AS "centerLat",
           ST_X(center::geometry) AS "centerLng"`,
        [name, slug, center.lng, center.lat, level, parentPinId ?? null],
      );

      return reply.status(201).send({ success: true, data: result[0] });
    },
  );

  // ─── PATCH /admin/pins/:id ── 핀 부분 수정
  fastify.patch(
    '/admin/pins/:id',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.SUPER_ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '핀 수정 (SUPER_ADMIN 전용)',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { name?: string; level?: string; isActive?: boolean };
      }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { name, level, isActive } = request.body ?? {};

      const pinRepo = AppDataSource.getRepository(Pin);
      const pin = await pinRepo.findOne({ where: { id } });
      if (!pin) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '핀을 찾을 수 없습니다.');
      }

      // 제공된 필드만 업데이트
      const updates: Partial<Pick<Pin, 'name' | 'isActive'>> & { level?: any } = {};
      if (name !== undefined) updates.name = name;
      if (level !== undefined) updates.level = level as any;
      if (isActive !== undefined) updates.isActive = isActive;

      if (Object.keys(updates).length === 0) {
        return reply.status(400).send({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: '수정할 필드를 하나 이상 제공해야 합니다.' },
        });
      }

      await pinRepo.update(id, updates);

      // geography 컬럼 직렬화 문제 회피를 위해 raw query로 최신 상태 반환
      const updated = await AppDataSource.query(
        `SELECT
           p.id,
           p.name,
           p.slug,
           p.level,
           p.parent_pin_id AS "parentPinId",
           p.region_code AS "regionCode",
           p.is_active AS "isActive",
           p.user_count AS "userCount",
           p.metadata,
           p.created_at AS "createdAt",
           ST_Y(p.center::geometry) AS "centerLat",
           ST_X(p.center::geometry) AS "centerLng"
         FROM pins p
         WHERE p.id = $1`,
        [id],
      );

      return reply.send({ success: true, data: updated[0] });
    },
  );

  // ─── PATCH /admin/pins/:id/deactivate ── 핀 비활성화
  fastify.patch(
    '/admin/pins/:id/deactivate',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.ADMIN)],
      schema: {
        tags: ['Admin'],
        summary: '핀 비활성화',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
      },
    },
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      const pinRepo = AppDataSource.getRepository(Pin);
      const pin = await pinRepo.findOne({ where: { id } });
      if (!pin) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '핀을 찾을 수 없습니다.');
      }

      await pinRepo.update(id, { isActive: false });

      return reply.send({
        success: true,
        data: { message: '핀이 비활성화되었습니다.', id },
      });
    },
  );
}
