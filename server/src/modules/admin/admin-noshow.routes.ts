import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';
import { MatchingService } from '../matching/matching.service.js';

export async function adminNoshowRoutes(fastify: FastifyInstance): Promise<void> {
  const matchingService = new MatchingService(
    AppDataSource,
    (global as any).__notificationService,
  );

  // ─── GET /admin/noshow-reports ── 노쇼 신고 목록
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
        Querystring: {
          status?: string;
          search?: string;
          page?: number;
          pageSize?: number;
        };
      }>,
      reply: FastifyReply,
    ) => {
      const { status, search } = request.query;
      const { page, pageSize, skip } = parsePageParams(request.query);

      let statusFilter = status ? `AND nr.status = '${status.replace(/'/g, "''")}'` : '';
      let searchFilter = '';
      const params: any[] = [pageSize, skip];
      if (search) {
        params.push(`%${search}%`);
        searchFilter = `AND (reporter.nickname ILIKE $${params.length} OR reported.nickname ILIKE $${params.length})`;
      }

      const rows = await AppDataSource.query(
        `SELECT
          nr.id,
          nr.match_id AS "matchId",
          nr.reporter_id AS "reporterId",
          reporter.nickname AS "reporterNickname",
          reporter.profile_image_url AS "reporterProfileImageUrl",
          nr.reported_user_id AS "reportedUserId",
          reported.nickname AS "reportedNickname",
          reported.profile_image_url AS "reportedProfileImageUrl",
          nr.reported_profile_id AS "reportedProfileId",
          nr.status,
          nr.evidence_urls AS "evidenceUrls",
          nr.reporter_message AS "reporterMessage",
          nr.admin_id AS "adminId",
          nr.admin_decision_at AS "adminDecisionAt",
          nr.admin_memo AS "adminMemo",
          nr.applied_score_change AS "appliedScoreChange",
          nr.applied_ban_hours AS "appliedBanHours",
          nr.created_at AS "createdAt",
          nr.updated_at AS "updatedAt",
          -- 신고 대상 컨텍스트
          rp.noshow_confirmed_count AS "reportedConfirmedCount",
          rp.manner_total AS "reportedMannerTotal",
          rp.manner_count AS "reportedMannerCount",
          -- 신고자 통계
          (SELECT COUNT(*) FROM noshow_reports WHERE reporter_id = nr.reporter_id)::int AS "reporterTotalReports",
          (SELECT COUNT(*) FROM noshow_reports WHERE reporter_id = nr.reporter_id AND status = 'APPROVED')::int AS "reporterApprovedReports",
          reporter_sp.manner_total AS "reporterMannerTotal",
          reporter_sp.manner_count AS "reporterMannerCount",
          -- 매칭 정보
          m.sport_type AS "matchSportType",
          m.status AS "matchStatus",
          m.chat_room_id AS "matchChatRoomId",
          m.scheduled_date AS "matchScheduledDate",
          m.created_at AS "matchCreatedAt",
          requester_u.nickname AS "matchRequesterNickname",
          opponent_u.nickname AS "matchOpponentNickname"
        FROM noshow_reports nr
        JOIN users reporter ON reporter.id = nr.reporter_id
        JOIN users reported ON reported.id = nr.reported_user_id
        JOIN sports_profiles rp ON rp.id = nr.reported_profile_id
        LEFT JOIN sports_profiles reporter_sp ON reporter_sp.user_id = nr.reporter_id AND reporter_sp.is_active = true
        LEFT JOIN matches m ON m.id = nr.match_id
        LEFT JOIN sports_profiles req_sp ON req_sp.id = m.requester_profile_id
        LEFT JOIN users requester_u ON requester_u.id = req_sp.user_id
        LEFT JOIN sports_profiles opp_sp ON opp_sp.id = m.opponent_profile_id
        LEFT JOIN users opponent_u ON opponent_u.id = opp_sp.user_id
        WHERE 1=1 ${statusFilter} ${searchFilter}
        ORDER BY nr.created_at DESC
        LIMIT $1 OFFSET $2`,
        params,
      );

      const countResult = await AppDataSource.query(
        `SELECT COUNT(*)::int AS total FROM noshow_reports nr
         JOIN users reporter ON reporter.id = nr.reporter_id
         JOIN users reported ON reported.id = nr.reported_user_id
         WHERE 1=1 ${statusFilter} ${searchFilter}`,
        search ? [`%${search}%`] : [],
      );
      const total = countResult[0]?.total ?? 0;

      const items = rows.map((r: any) => ({
        id: r.id,
        matchId: r.matchId,
        reporterId: r.reporterId,
        reporterNickname: r.reporterNickname,
        reporterProfileImageUrl: r.reporterProfileImageUrl,
        reporterMannerAvg: r.reporterMannerCount > 0
          ? Number((r.reporterMannerTotal / r.reporterMannerCount).toFixed(2))
          : null,
        reporterTotalReports: r.reporterTotalReports,
        reporterApprovedReports: r.reporterApprovedReports,
        reportedUserId: r.reportedUserId,
        reportedNickname: r.reportedNickname,
        reportedProfileImageUrl: r.reportedProfileImageUrl,
        reportedProfileId: r.reportedProfileId,
        reportedConfirmedCount: r.reportedConfirmedCount,
        reportedMannerAvg: r.reportedMannerCount > 0
          ? Number((r.reportedMannerTotal / r.reportedMannerCount).toFixed(2))
          : null,
        status: r.status,
        evidenceUrls: r.evidenceUrls,
        reporterMessage: r.reporterMessage,
        adminId: r.adminId,
        adminDecisionAt: r.adminDecisionAt,
        adminMemo: r.adminMemo,
        appliedScoreChange: r.appliedScoreChange,
        appliedBanHours: r.appliedBanHours,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        match: r.matchId ? {
          id: r.matchId,
          sportType: r.matchSportType,
          status: r.matchStatus,
          chatRoomId: r.matchChatRoomId,
          scheduledDate: r.matchScheduledDate,
          createdAt: r.matchCreatedAt,
          requesterNickname: r.matchRequesterNickname,
          opponentNickname: r.matchOpponentNickname,
        } : null,
      }));

      return reply.send({ success: true, data: paginatedResponse(items, total, page, pageSize) });
    },
  );

  // ─── GET /admin/noshow-reports/pending-count ── PENDING 카운트
  fastify.get(
    '/admin/noshow-reports/pending-count',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: 'PENDING 노쇼 신고 카운트',
        security: [{ bearerAuth: [] }],
      },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const result = await AppDataSource.query(
        `SELECT
          COUNT(*)::int AS "pendingCount",
          COUNT(*) FILTER (WHERE created_at < NOW() - INTERVAL '24 hours')::int AS "overdueCount"
         FROM noshow_reports
         WHERE status = 'PENDING'`,
      );
      return reply.send({
        success: true,
        data: {
          pendingCount: result[0]?.pendingCount ?? 0,
          overdueCount: result[0]?.overdueCount ?? 0,
        },
      });
    },
  );

  // ─── POST /admin/noshow-reports/:id/approve ── 승인
  fastify.post(
    '/admin/noshow-reports/:id/approve',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '노쇼 신고 승인',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['memo'],
          properties: { memo: { type: 'string', minLength: 1 } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { memo: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { memo } = request.body;
      const adminRole = (request as any).adminRole as AdminRole;

      // 영구 정지 여부 미리 확인 (MODERATOR가 2회+ APPROVED 처리 시 422)
      const reportRow = await AppDataSource.query(
        `SELECT nr.reported_profile_id, sp.noshow_confirmed_count
         FROM noshow_reports nr
         JOIN sports_profiles sp ON sp.id = nr.reported_profile_id
         WHERE nr.id = $1`,
        [id],
      );
      if (reportRow.length === 0) {
        throw AppError.notFound(ErrorCode.NOT_FOUND, '노쇼 신고를 찾을 수 없습니다.');
      }

      const confirmedCount: number = reportRow[0].noshow_confirmed_count ?? 0;
      const wouldBePermanent = confirmedCount + 1 >= 2;

      if (wouldBePermanent && adminRole !== AdminRole.SUPER_ADMIN) {
        return reply.status(422).send({
          success: false,
          error: {
            code: 'SUPER_ADMIN_REQUIRED',
            message: '2회 이상 누적 노쇼로 영구 정지 처리가 필요합니다. SUPER_ADMIN 승인이 필요합니다.',
          },
        });
      }

      const result = await matchingService.approveNoshowReport(id, request.user.userId, memo);
      return reply.send({ success: true, data: result });
    },
  );

  // ─── POST /admin/noshow-reports/:id/reject ── 기각
  fastify.post(
    '/admin/noshow-reports/:id/reject',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '노쇼 신고 기각',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['memo'],
          properties: {
            memo: { type: 'string', minLength: 1 },
            reporterPenalty: { type: 'boolean' },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{
        Params: { id: string };
        Body: { memo: string; reporterPenalty?: boolean };
      }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { memo, reporterPenalty = false } = request.body;
      const result = await matchingService.rejectNoshowReport(
        id,
        request.user.userId,
        memo,
        reporterPenalty,
      );
      return reply.send({ success: true, data: result });
    },
  );

  // ─── POST /admin/noshow-reports/:id/insufficient ── 자료 요청
  fastify.post(
    '/admin/noshow-reports/:id/insufficient',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '노쇼 신고 자료 부족 처리',
        security: [{ bearerAuth: [] }],
        params: { type: 'object', properties: { id: { type: 'string', format: 'uuid' } } },
        body: {
          type: 'object',
          required: ['memo'],
          properties: { memo: { type: 'string', minLength: 1 } },
        },
      },
    },
    async (
      request: FastifyRequest<{ Params: { id: string }; Body: { memo: string } }>,
      reply: FastifyReply,
    ) => {
      const { id } = request.params;
      const { memo } = request.body;
      const result = await matchingService.requestMoreEvidence(id, request.user.userId, memo);
      return reply.send({ success: true, data: result });
    },
  );

  // ─── POST /admin/noshow-reports/bulk-reject ── 일괄 기각
  fastify.post(
    '/admin/noshow-reports/bulk-reject',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '노쇼 신고 일괄 기각',
        security: [{ bearerAuth: [] }],
        body: {
          type: 'object',
          required: ['ids', 'memo'],
          properties: {
            ids: { type: 'array', items: { type: 'string', format: 'uuid' }, minItems: 1 },
            memo: { type: 'string', minLength: 1 },
          },
        },
      },
    },
    async (
      request: FastifyRequest<{ Body: { ids: string[]; memo: string } }>,
      reply: FastifyReply,
    ) => {
      const { ids, memo } = request.body;
      const adminId = request.user.userId;

      const results = await Promise.allSettled(
        ids.map((id) => matchingService.rejectNoshowReport(id, adminId, memo, false)),
      );

      const succeeded = results.filter((r) => r.status === 'fulfilled').length;
      const failed = results.filter((r) => r.status === 'rejected').length;

      return reply.send({
        success: true,
        data: { message: `${succeeded}건 기각 완료, ${failed}건 실패.` },
      });
    },
  );
}
