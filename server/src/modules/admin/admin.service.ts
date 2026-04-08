import { AppDataSource } from '../../config/database.js';
import {
  User,
  Match,
  Report,
  Game,
  Pin,
  AdminProfile,
  AdminRole,
  UserStatus,
  GameResultStatus,
} from '../../entities/index.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { calculateTier } from '../../shared/utils/elo.js';

export class AdminService {
  // ─────────────────────────────────────
  // 대시보드 지표
  // ─────────────────────────────────────

  async getDashboard() {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today.getTime() - 86400000);
    const thirtyDaysAgo = new Date(today.getTime() - 30 * 86400000);

    const userRepo = AppDataSource.getRepository(User);
    const matchRepo = AppDataSource.getRepository(Match);
    const reportRepo = AppDataSource.getRepository(Report);

    const [
      totalUsers,
      activeUsers,
      newSignups,
      totalMatches,
      completedMatches,
      pendingReports,
    ] = await Promise.all([
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
      matchRepo
        .createQueryBuilder('match')
        .where('match.createdAt >= :date', { date: today })
        .getCount(),
      matchRepo
        .createQueryBuilder('match')
        .where('match.status = :status', { status: 'COMPLETED' })
        .andWhere('match.completedAt >= :date', { date: today })
        .getCount(),
      reportRepo
        .createQueryBuilder('report')
        .where('report.status = :status', { status: 'PENDING' })
        .getCount(),
    ]);

    const matchSuccessRate =
      totalMatches > 0 ? Math.round((completedMatches / totalMatches) * 100) : 0;

    return {
      summary: {
        totalUsers,
        activeUsers,
        newSignups,
        matchesCreated: totalMatches,
        matchesCompleted: completedMatches,
        pendingReports,
      },
      matchSuccessRate,
      generatedAt: new Date(),
    };
  }

  // ─────────────────────────────────────
  // 사용자 관리
  // ─────────────────────────────────────

  async listUsers(opts: {
    status?: UserStatus;
    search?: string;
    cursor?: string;
    limit?: number;
  }) {
    const { status, search, cursor, limit = 20 } = opts;

    const userRepo = AppDataSource.getRepository(User);
    const qb = userRepo
      .createQueryBuilder('user')
      .leftJoinAndSelect('user.sportsProfiles', 'sportsProfile', 'sportsProfile.isActive = true');

    if (status) {
      qb.andWhere('user.status = :status', { status });
    }
    if (search) {
      qb.andWhere('(user.nickname ILIKE :search OR user.email ILIKE :search)', {
        search: `%${search}%`,
      });
    }
    if (cursor) {
      qb.andWhere('user.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const users = await qb
      .orderBy('user.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = users.length > limit;
    const items = hasMore ? users.slice(0, limit) : users;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  async suspendUser(userId: string, reason: string): Promise<void> {
    const userRepo = AppDataSource.getRepository(User);
    const user = await userRepo.findOne({ where: { id: userId } });
    if (!user) throw AppError.notFound(ErrorCode.USER_NOT_FOUND);

    await userRepo.update(userId, { status: 'SUSPENDED' as any });
  }

  async activateUser(userId: string): Promise<void> {
    const userRepo = AppDataSource.getRepository(User);
    await userRepo.update(userId, { status: 'ACTIVE' as any });
  }

  // ─────────────────────────────────────
  // 신고 처리
  // ─────────────────────────────────────

  async listReports(opts: {
    status?: string;
    targetType?: string;
    cursor?: string;
    limit?: number;
  }) {
    const { status, targetType, cursor, limit = 20 } = opts;

    const reportRepo = AppDataSource.getRepository(Report);
    const qb = reportRepo
      .createQueryBuilder('report')
      .leftJoinAndSelect('report.reporter', 'reporter');

    if (status) {
      qb.andWhere('report.status = :status', { status });
    }
    if (targetType) {
      qb.andWhere('report.targetType = :targetType', { targetType });
    }
    if (cursor) {
      qb.andWhere('report.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const reports = await qb
      .orderBy('report.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = reports.length > limit;
    const items = hasMore ? reports.slice(0, limit) : reports;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  async resolveReport(
    reportId: string,
    resolverUserId: string,
    action: 'RESOLVED' | 'DISMISSED',
  ): Promise<void> {
    const reportRepo = AppDataSource.getRepository(Report);
    const report = await reportRepo.findOne({ where: { id: reportId } });
    if (!report) throw AppError.notFound(ErrorCode.NOT_FOUND, '신고를 찾을 수 없습니다.');

    await reportRepo.update(reportId, {
      status: action as any,
      resolvedBy: resolverUserId,
      resolvedAt: new Date(),
    });
  }

  // ─────────────────────────────────────
  // 경기 결과 관리 (이의 신청 처리)
  // ─────────────────────────────────────

  async listDisputedGames(opts: { cursor?: string; limit?: number } = {}) {
    const { cursor, limit = 20 } = opts;

    const gameRepo = AppDataSource.getRepository(Game);
    const qb = gameRepo
      .createQueryBuilder('game')
      .leftJoinAndSelect('game.match', 'match')
      .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
      .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
      .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
      .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
      .where('game.resultStatus = :status', { status: 'DISPUTED' });

    if (cursor) {
      qb.andWhere('game.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const games = await qb
      .orderBy('game.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = games.length > limit;
    const items = hasMore ? games.slice(0, limit) : games;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  async resolveDispute(
    gameId: string,
    adminUserId: string,
    resolution: {
      action: 'KEEP_ORIGINAL' | 'MODIFY_RESULT' | 'VOID_GAME';
      requesterScore?: number;
      opponentScore?: number;
      winnerId?: string;
    },
  ) {
    const gameRepo = AppDataSource.getRepository(Game);
    const game = await gameRepo.findOne({
      where: { id: gameId },
      relations: ['match', 'match.requesterProfile', 'match.opponentProfile'],
    });

    if (!game) throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);

    const matchRepo = AppDataSource.getRepository(Match);

    if (resolution.action === 'VOID_GAME') {
      await AppDataSource.transaction(async (manager) => {
        await manager.getRepository(Game).update(gameId, { resultStatus: 'VOIDED' as any });
        await manager.getRepository(Match).update(game.matchId, { status: 'CANCELLED' as any });
      });
    } else if (resolution.action === 'MODIFY_RESULT') {
      await gameRepo.update(gameId, {
        resultStatus: 'VERIFIED' as any,
        requesterScore: resolution.requesterScore ?? null,
        opponentScore: resolution.opponentScore ?? null,
        winnerProfileId: resolution.winnerId ?? null,
        verifiedAt: new Date(),
      });
    } else {
      // KEEP_ORIGINAL
      await gameRepo.update(gameId, { resultStatus: 'VERIFIED' as any, verifiedAt: new Date() });
    }
  }

  // ─────────────────────────────────────
  // 핀 관리
  // ─────────────────────────────────────

  async listPins(opts: {
    level?: string;
    active?: boolean;
    cursor?: string;
    limit?: number;
  } = {}) {
    const { level, active, cursor, limit = 50 } = opts;

    const pinRepo = AppDataSource.getRepository(Pin);
    const qb = pinRepo.createQueryBuilder('pin');

    if (level) {
      qb.andWhere('pin.level = :level', { level });
    }
    if (active !== undefined) {
      qb.andWhere('pin.isActive = :active', { active });
    }
    if (cursor) {
      qb.andWhere('pin.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const pins = await qb
      .orderBy('pin.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = pins.length > limit;
    const items = hasMore ? pins.slice(0, limit) : pins;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  async activatePin(pinId: string, active: boolean): Promise<void> {
    const pinRepo = AppDataSource.getRepository(Pin);
    await pinRepo.update(pinId, { isActive: active });
  }

  // ─────────────────────────────────────
  // 어드민 계정 관리
  // ─────────────────────────────────────

  async grantAdminRole(
    targetUserId: string,
    role: AdminRole,
    grantedBy: string,
  ): Promise<void> {
    const adminProfileRepo = AppDataSource.getRepository(AdminProfile);
    const existing = await adminProfileRepo.findOne({ where: { userId: targetUserId } });

    if (existing) {
      await adminProfileRepo.update(existing.id, { role });
    } else {
      const profile = adminProfileRepo.create({ userId: targetUserId, role });
      await adminProfileRepo.save(profile);
    }
  }

  async revokeAdminRole(targetUserId: string): Promise<void> {
    const adminProfileRepo = AppDataSource.getRepository(AdminProfile);
    await adminProfileRepo.delete({ userId: targetUserId });
  }
}
