import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import { redis } from '../../config/redis.js';

export async function adminAnalyticsRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/analytics/dashboard ── 분석 대시보드 전체 데이터
  fastify.get(
    '/admin/analytics/dashboard',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: {
        tags: ['Admin'],
        summary: '앱 사용자 분석 대시보드',
        security: [{ bearerAuth: [] }],
      },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD (UTC)
      const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];

      // 1. 실시간 접속자 (현재 소켓 연결된 유저)
      const [onlineCount, onlineUsers] = await Promise.all([
        redis.scard('online_users'),
        redis.smembers('online_users'),
      ]);

      // 2. 오늘 접속자 (DAU) + 어제 DAU (비교용)
      const [dauCount, yesterdayDau] = await Promise.all([
        redis.scard(`dau:${today}`),
        redis.scard(`dau:${yesterday}`),
      ]);

      // 3. 시간대별 접속자 (0~23시, UTC 기준)
      const hourlyData: { hour: number; count: number }[] = [];
      const hourlyPromises = Array.from({ length: 24 }, (_, h) =>
        redis.scard(`hourly:${today}:${h}`),
      );
      const hourlyCounts = await Promise.all(hourlyPromises);
      for (let h = 0; h < 24; h++) {
        hourlyData.push({ hour: h, count: hourlyCounts[h] });
      }

      // 4. 평균 체류 시간 (초) — 오늘 종료된 세션 기준
      const sessions = await redis.lrange(`sessions:${today}`, 0, -1);
      const sessionDurations = sessions.map(Number).filter((d) => d > 0);
      const totalSessions = sessionDurations.length;
      const avgSessionDuration =
        totalSessions > 0
          ? Math.round(sessionDurations.reduce((a, b) => a + b, 0) / totalSessions)
          : 0;

      // 5~8. DB 조회 (병렬)
      const [totalUsersResult, newUsersTodayResult, activeMatchesResult, completedTodayResult] =
        await Promise.all([
          // 5. 총 가입자 수 (ACTIVE 상태 유저)
          AppDataSource.query(
            `SELECT COUNT(*) AS count FROM users WHERE status = 'ACTIVE'`,
          ),
          // 6. 오늘 신규 가입자
          AppDataSource.query(
            `SELECT COUNT(*) AS count FROM users WHERE created_at::date = $1`,
            [today],
          ),
          // 7. 활성 매칭 수
          AppDataSource.query(
            `SELECT COUNT(*) AS count FROM matches WHERE status IN ('PENDING_ACCEPT', 'CHAT', 'CONFIRMED')`,
          ),
          // 8. 오늘 완료 매칭 수
          AppDataSource.query(
            `SELECT COUNT(*) AS count FROM matches WHERE completed_at::date = $1`,
            [today],
          ),
        ]);

      const totalUsers = parseInt(totalUsersResult[0]?.count ?? '0', 10);
      const newUsersToday = parseInt(newUsersTodayResult[0]?.count ?? '0', 10);
      const activeMatches = parseInt(activeMatchesResult[0]?.count ?? '0', 10);
      const completedMatchesToday = parseInt(completedTodayResult[0]?.count ?? '0', 10);

      return reply.send({
        success: true,
        data: {
          realtime: {
            onlineCount,
            onlineUserIds: onlineUsers,
          },
          today: {
            dau: dauCount,
            yesterdayDau,
            newUsers: newUsersToday,
            completedMatches: completedMatchesToday,
            totalSessions,
            avgSessionDurationSeconds: avgSessionDuration,
            avgSessionDurationFormatted: `${Math.floor(avgSessionDuration / 60)}분 ${avgSessionDuration % 60}초`,
          },
          total: {
            users: totalUsers,
            activeMatches,
          },
          hourly: hourlyData,
          generatedAt: new Date().toISOString(),
        },
      });
    },
  );
}
