import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { AdminRole, MatchStatus } from '../../entities/index.js';
import { requireAdmin } from './admin.middleware.js';
import { AppDataSource } from '../../config/database.js';
import {
  User,
  Match,
  Game,
  Report,
  Pin,
  Team,
} from '../../entities/index.js';

export async function adminDashboardRoutes(fastify: FastifyInstance): Promise<void> {
  // ─── GET /admin/dashboard/metrics ── 대시보드 종합 지표
  fastify.get(
    '/admin/dashboard/metrics',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '대시보드 종합 지표', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const thisWeekStart = new Date(today.getTime() - 7 * 86400000);
      const thirtyDaysAgo = new Date(today.getTime() - 30 * 86400000);

      const userRepo = AppDataSource.getRepository(User);
      const matchRepo = AppDataSource.getRepository(Match);
      const gameRepo = AppDataSource.getRepository(Game);
      const reportRepo = AppDataSource.getRepository(Report);
      const pinRepo = AppDataSource.getRepository(Pin);
      const teamRepo = AppDataSource.getRepository(Team);

      const [
        // users
        totalUsers,
        activeUsers,
        newTodayUsers,
        newThisWeekUsers,
        suspendedUsers,
        // matches
        totalMatches,
        activeMatches,
        completedTodayMatches,
        completedThisWeekMatches,
        // games
        totalGames,
        disputedGames,
        verifiedGames,
        pendingResultGames,
        // reports
        totalReports,
        pendingReports,
        resolvedTodayReports,
        // pins
        totalPins,
        activePins,
        // teams
        totalTeams,
        activeTeams,
      ] = await Promise.all([
        // users
        userRepo.count(),
        userRepo
          .createQueryBuilder('user')
          .where('user.status = :status', { status: 'ACTIVE' })
          .andWhere('user.lastLoginAt >= :date', { date: thirtyDaysAgo })
          .getCount(),
        userRepo
          .createQueryBuilder('user')
          .where('user.createdAt >= :date', { date: today })
          .getCount(),
        userRepo
          .createQueryBuilder('user')
          .where('user.createdAt >= :date', { date: thisWeekStart })
          .getCount(),
        userRepo
          .createQueryBuilder('user')
          .where('user.status = :status', { status: 'SUSPENDED' })
          .getCount(),

        // matches
        matchRepo.count(),
        matchRepo
          .createQueryBuilder('match')
          .where('match.status NOT IN (:...statuses)', {
            statuses: [MatchStatus.COMPLETED, MatchStatus.CANCELLED],
          })
          .getCount(),
        matchRepo
          .createQueryBuilder('match')
          .where('match.status = :status', { status: MatchStatus.COMPLETED })
          .andWhere('match.completedAt >= :date', { date: today })
          .getCount(),
        matchRepo
          .createQueryBuilder('match')
          .where('match.status = :status', { status: MatchStatus.COMPLETED })
          .andWhere('match.completedAt >= :date', { date: thisWeekStart })
          .getCount(),

        // games
        gameRepo.count(),
        gameRepo
          .createQueryBuilder('game')
          .where('game.resultStatus = :status', { status: 'DISPUTED' })
          .getCount(),
        gameRepo
          .createQueryBuilder('game')
          .where('game.resultStatus = :status', { status: 'VERIFIED' })
          .getCount(),
        gameRepo
          .createQueryBuilder('game')
          .where('game.resultStatus IN (:...statuses)', {
            statuses: ['PENDING', 'PROOF_UPLOADED'],
          })
          .getCount(),

        // reports
        reportRepo.count(),
        reportRepo
          .createQueryBuilder('report')
          .where('report.status = :status', { status: 'PENDING' })
          .getCount(),
        reportRepo
          .createQueryBuilder('report')
          .where('report.status IN (:...statuses)', { statuses: ['RESOLVED', 'DISMISSED'] })
          .andWhere('report.resolvedAt >= :date', { date: today })
          .getCount(),

        // pins
        pinRepo.count(),
        pinRepo
          .createQueryBuilder('pin')
          .where('pin.isActive = :active', { active: true })
          .getCount(),

        // teams
        teamRepo.count(),
        teamRepo
          .createQueryBuilder('team')
          .where('team.status = :status', { status: 'ACTIVE' })
          .getCount(),
      ]);

      const successRate =
        totalMatches > 0
          ? Math.round((completedThisWeekMatches / totalMatches) * 100)
          : 0;

      return reply.send({
        success: true,
        data: {
          users: {
            total: totalUsers,
            active: activeUsers,
            newToday: newTodayUsers,
            newThisWeek: newThisWeekUsers,
            suspended: suspendedUsers,
          },
          matches: {
            total: totalMatches,
            active: activeMatches,
            completedToday: completedTodayMatches,
            completedThisWeek: completedThisWeekMatches,
            successRate,
          },
          games: {
            total: totalGames,
            disputed: disputedGames,
            verified: verifiedGames,
            pendingResults: pendingResultGames,
          },
          reports: {
            total: totalReports,
            pending: pendingReports,
            resolvedToday: resolvedTodayReports,
          },
          pins: {
            total: totalPins,
            active: activePins,
          },
          teams: {
            total: totalTeams,
            active: activeTeams,
          },
          generatedAt: now,
        },
      });
    },
  );

  // ─── GET /admin/dashboard/realtime ── 실시간 현황
  fastify.get(
    '/admin/dashboard/realtime',
    {
      onRequest: [fastify.authenticate, requireAdmin(AdminRole.MODERATOR)],
      schema: { tags: ['Admin'], summary: '실시간 현황', security: [{ bearerAuth: [] }] },
    },
    async (_request: FastifyRequest, reply: FastifyReply) => {
      const last24h = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const userRepo = AppDataSource.getRepository(User);
      const matchRepo = AppDataSource.getRepository(Match);
      const reportRepo = AppDataSource.getRepository(Report);

      const [activeUsersCount, ongoingMatchesCount, pendingReportsCount, recentSignupUsers] =
        await Promise.all([
          // 최근 24시간 이내 로그인한 유저
          userRepo
            .createQueryBuilder('user')
            .where('user.lastLoginAt >= :date', { date: last24h })
            .getCount(),

          // 진행 중인 매치 (CHAT, CONFIRMED, PENDING_ACCEPT)
          matchRepo
            .createQueryBuilder('match')
            .where('match.status IN (:...statuses)', {
              statuses: ['CHAT', 'CONFIRMED', 'PENDING_ACCEPT'],
            })
            .getCount(),

          // 대기 중인 신고
          reportRepo
            .createQueryBuilder('report')
            .where('report.status = :status', { status: 'PENDING' })
            .getCount(),

          // 최근 가입 5명
          userRepo
            .createQueryBuilder('user')
            .select(['user.id', 'user.nickname', 'user.createdAt'])
            .orderBy('user.createdAt', 'DESC')
            .take(5)
            .getMany(),
        ]);

      return reply.send({
        success: true,
        data: {
          activeUsers: activeUsersCount,
          ongoingMatches: ongoingMatchesCount,
          pendingReports: pendingReportsCount,
          recentSignups: recentSignupUsers.map((u) => ({
            id: u.id,
            nickname: u.nickname,
            createdAt: u.createdAt,
          })),
        },
      });
    },
  );
}
