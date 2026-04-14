import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';

export async function adminDashboardRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/dashboard/metrics ── 대시보드 종합 지표 (DashboardMetrics 타입 준수)
  fastify.get(
    '/admin/dashboard/metrics',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '대시보드 종합 지표', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const now = new Date();
      // 오늘 자정 (로컬 기준 날짜 문자열, PostgreSQL date 비교용)
      const todayStr = now.toISOString().split('T')[0]; // YYYY-MM-DD
      const last24h = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

      // 모든 집계 쿼리를 병렬 실행
      const [
        // realtime
        activeUsersResult,
        activeMatchRequestsResult,
        ongoingMatchesResult,
        pendingResultVerificationsResult,
        // today
        newSignupsResult,
        matchesCreatedResult,
        matchesCompletedResult,
        reportsReceivedResult,
        // charts - match success rate
        totalMatchesResult,
        completedMatchesResult,
        // charts - DAU trend (raw SQL)
        dauTrendResult,
        // charts - score distribution (raw SQL)
        scoreDistributionResult,
      ] = await Promise.all([
        // ── realtime: 최근 24시간 로그인 유저 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM users WHERE last_login_at >= $1`,
          [last24h],
        ),

        // ── realtime: 활성 매칭 요청 수 (WAITING 상태 = 상대를 기다리는 중)
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM match_requests WHERE status = 'WAITING' AND expires_at > NOW()`,
        ),

        // ── realtime: 진행 중인 매치 수 (PENDING_ACCEPT, CHAT, CONFIRMED)
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM matches WHERE status IN ('PENDING_ACCEPT', 'CHAT', 'CONFIRMED')`,
        ),

        // ── realtime: 결과 인증 대기 게임 수 (PENDING, PROOF_UPLOADED)
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM games WHERE result_status IN ('PENDING', 'PROOF_UPLOADED')`,
        ),

        // ── today: 오늘 신규 가입자
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM users WHERE created_at::date = $1::date`,
          [todayStr],
        ),

        // ── today: 오늘 생성된 매치 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM matches WHERE created_at::date = $1::date`,
          [todayStr],
        ),

        // ── today: 오늘 완료된 매치 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM matches WHERE status = 'COMPLETED' AND completed_at::date = $1::date`,
          [todayStr],
        ),

        // ── today: 오늘 접수된 신고 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM reports WHERE created_at::date = $1::date`,
          [todayStr],
        ),

        // ── charts.matchSuccessRate: 전체 매치 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM matches`,
        ),

        // ── charts.matchSuccessRate: 완료된 매치 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM matches WHERE status = 'COMPLETED'`,
        ),

        // ── charts.dauTrend: 최근 30일 일별 활성 사용자 (last_login_at 기준)
        AppDataSource.query<{ login_date: string; dau: string }[]>(
          `SELECT
            TO_CHAR(last_login_at AT TIME ZONE 'Asia/Seoul', 'MM/DD') AS login_date,
            COUNT(DISTINCT id) AS dau
          FROM users
          WHERE last_login_at >= $1
            AND last_login_at IS NOT NULL
          GROUP BY TO_CHAR(last_login_at AT TIME ZONE 'Asia/Seoul', 'MM/DD'),
                   DATE_TRUNC('day', last_login_at AT TIME ZONE 'Asia/Seoul')
          ORDER BY DATE_TRUNC('day', last_login_at AT TIME ZONE 'Asia/Seoul') ASC`,
          [thirtyDaysAgo],
        ),

        // ── charts.scoreDistribution: sports_profiles.current_score 100점 단위 버킷 분포
        AppDataSource.query<{ range_start: string; range_end: string; count: string }[]>(
          `SELECT
            (FLOOR(current_score / 100) * 100)::int AS range_start,
            (FLOOR(current_score / 100) * 100 + 99)::int AS range_end,
            COUNT(*) AS count
          FROM sports_profiles
          WHERE is_active = TRUE
          GROUP BY FLOOR(current_score / 100)
          ORDER BY range_start ASC`,
        ),
      ]);

      // 집계 값 파싱
      const activeUsers = parseInt(activeUsersResult[0]?.count ?? '0', 10);
      const activeMatchRequests = parseInt(activeMatchRequestsResult[0]?.count ?? '0', 10);
      const ongoingMatches = parseInt(ongoingMatchesResult[0]?.count ?? '0', 10);
      const pendingResultVerifications = parseInt(pendingResultVerificationsResult[0]?.count ?? '0', 10);

      const newSignups = parseInt(newSignupsResult[0]?.count ?? '0', 10);
      const matchesCreated = parseInt(matchesCreatedResult[0]?.count ?? '0', 10);
      const matchesCompleted = parseInt(matchesCompletedResult[0]?.count ?? '0', 10);
      const reportsReceived = parseInt(reportsReceivedResult[0]?.count ?? '0', 10);

      const totalMatches = parseInt(totalMatchesResult[0]?.count ?? '0', 10);
      const completedMatches = parseInt(completedMatchesResult[0]?.count ?? '0', 10);
      const matchSuccessRate = totalMatches > 0
        ? Math.round((completedMatches / totalMatches) * 1000) / 1000 // 소수점 3자리 (예: 0.682)
        : 0;

      // DAU 트렌드: DB에 없는 날짜는 0으로 채워서 최근 30일 완전한 배열 반환
      const dauMap = new Map<string, number>();
      for (const row of dauTrendResult) {
        dauMap.set(row.login_date, parseInt(row.dau, 10));
      }
      const dauTrend: { date: string; value: number }[] = [];
      for (let i = 29; i >= 0; i--) {
        const d = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
        // KST 기준 MM/DD 포맷
        const kstDate = new Date(d.getTime() + 9 * 60 * 60 * 1000);
        const label = `${String(kstDate.getUTCMonth() + 1).padStart(2, '0')}/${String(kstDate.getUTCDate()).padStart(2, '0')}`;
        dauTrend.push({ date: label, value: dauMap.get(label) ?? 0 });
      }

      // 점수 분포 버킷
      const scoreDistributionBuckets = scoreDistributionResult.map((row) => ({
        rangeStart: parseInt(row.range_start, 10),
        rangeEnd: parseInt(row.range_end, 10),
        count: parseInt(row.count, 10),
      }));

      return reply.send({
        success: true,
        data: {
          realtime: {
            activeUsers,
            activeMatchRequests,
            ongoingMatches,
            pendingResultVerifications,
          },
          today: {
            newSignups,
            matchesCreated,
            matchesCompleted,
            reportsReceived,
          },
          charts: {
            dauTrend,
            matchSuccessRate,
            regionHeatmap: { points: [] }, // 추후 구현
            scoreDistribution: { buckets: scoreDistributionBuckets },
          },
          generatedAt: now,
        },
      });
    },
  );

  // ─── GET /admin/dashboard/realtime ── 실시간 현황 (DashboardMetrics['realtime'] 타입 준수)
  fastify.get(
    '/admin/dashboard/realtime',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '실시간 현황', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const last24h = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const [
        activeUsersResult,
        activeMatchRequestsResult,
        ongoingMatchesResult,
        pendingResultVerificationsResult,
      ] = await Promise.all([
        // 최근 24시간 이내 로그인한 유저
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM users WHERE last_login_at >= $1`,
          [last24h],
        ),

        // 활성 매칭 요청 수 (WAITING 상태)
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM match_requests WHERE status = 'WAITING' AND expires_at > NOW()`,
        ),

        // 진행 중인 매치 (PENDING_ACCEPT, CHAT, CONFIRMED)
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM matches WHERE status IN ('PENDING_ACCEPT', 'CHAT', 'CONFIRMED')`,
        ),

        // 결과 인증 대기 게임 수
        AppDataSource.query<{ count: string }[]>(
          `SELECT COUNT(*) AS count FROM games WHERE result_status IN ('PENDING', 'PROOF_UPLOADED')`,
        ),
      ]);

      return reply.send({
        success: true,
        data: {
          activeUsers: parseInt(activeUsersResult[0]?.count ?? '0', 10),
          activeMatchRequests: parseInt(activeMatchRequestsResult[0]?.count ?? '0', 10),
          ongoingMatches: parseInt(ongoingMatchesResult[0]?.count ?? '0', 10),
          pendingResultVerifications: parseInt(pendingResultVerificationsResult[0]?.count ?? '0', 10),
        },
      });
    },
  );
}
