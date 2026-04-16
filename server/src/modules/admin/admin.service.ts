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
import { parsePageParams, paginatedResponse } from '../../shared/pagination.js';

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
    page?: number;
    pageSize?: number;
  }) {
    const { status, search } = opts;
    const { page, pageSize, skip } = parsePageParams(opts);

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

    const [items, total] = await qb
      .orderBy('user.createdAt', 'DESC')
      .skip(skip)
      .take(pageSize)
      .getManyAndCount();

    return paginatedResponse(items, total, page, pageSize);
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
    page?: number;
    pageSize?: number;
  }) {
    const { status, targetType } = opts;
    const { page, pageSize, skip } = parsePageParams(opts);

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

    const [items, total] = await qb
      .orderBy('report.createdAt', 'DESC')
      .skip(skip)
      .take(pageSize)
      .getManyAndCount();

    return paginatedResponse(items, total, page, pageSize);
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

  async listDisputedGames(opts: { page?: number; pageSize?: number } = {}) {
    const { page, pageSize, skip } = parsePageParams(opts);

    const gameRepo = AppDataSource.getRepository(Game);
    const qb = gameRepo
      .createQueryBuilder('game')
      .leftJoinAndSelect('game.match', 'match')
      .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
      .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
      .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
      .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
      .where('game.resultStatus = :status', { status: 'DISPUTED' });

    const [items, total] = await qb
      .orderBy('game.createdAt', 'DESC')
      .skip(skip)
      .take(pageSize)
      .getManyAndCount();

    return paginatedResponse(items, total, page, pageSize);
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
    page?: number;
    pageSize?: number;
  } = {}) {
    const { level, active } = opts;
    const { page, pageSize, skip } = parsePageParams(opts);

    // geography(center) 직렬화 문제 회피: raw SQL + ST_Y/ST_X 사용
    const conditions: string[] = [];
    const params: any[] = [];
    let paramIdx = 1;

    if (level) {
      conditions.push(`p.level = $${paramIdx++}`);
      params.push(level);
    }
    if (active !== undefined) {
      conditions.push(`p.is_active = $${paramIdx++}`);
      params.push(active);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const [countResult, items] = await Promise.all([
      AppDataSource.query<{ count: string }[]>(
        `SELECT COUNT(*) AS count FROM pins p ${whereClause}`,
        params,
      ),
      AppDataSource.query(
        `SELECT
           p.id, p.name, p.slug, p.level,
           p.parent_pin_id AS "parentPinId",
           p.region_code AS "regionCode",
           p.is_active AS "isActive",
           p.user_count AS "userCount",
           p.metadata,
           p.created_at AS "createdAt",
           json_build_object('lat', ST_Y(p.center::geometry), 'lng', ST_X(p.center::geometry)) AS center
         FROM pins p
         ${whereClause}
         ORDER BY p.created_at DESC
         OFFSET $${paramIdx} LIMIT $${paramIdx + 1}`,
        [...params, skip, pageSize],
      ),
    ]);

    const total = parseInt(countResult[0]?.count ?? '0', 10);
    return paginatedResponse(items, total, page, pageSize);
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
