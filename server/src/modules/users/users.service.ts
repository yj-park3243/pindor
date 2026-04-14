import { DataSource } from 'typeorm';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { updateUserHomeLocation } from '../../shared/utils/geo.js';
import { getTierInfo } from '../../shared/utils/elo.js';
import { User, SportsProfile, Game, UserStatus } from '../../entities/index.js';
import type { UpdateUserDto, UpdateLocationDto } from './users.schema.js';

export class UsersService {
  constructor(private dataSource: DataSource) {}

  // ─────────────────────────────────────
  // 닉네임 중복 확인
  // ─────────────────────────────────────

  async checkNickname(nickname: string, excludeUserId?: string): Promise<boolean> {
    if (excludeUserId) {
      const rows = await this.dataSource.query(
        `SELECT id FROM users WHERE nickname = $1 AND id != $2::uuid LIMIT 1`,
        [nickname, excludeUserId],
      );
      return rows.length === 0;
    }
    const userRepo = this.dataSource.getRepository(User);
    const existing = await userRepo.findOne({ where: { nickname } });
    return !existing;
  }

  // ─────────────────────────────────────
  // 내 정보 조회
  // ─────────────────────────────────────

  async getMe(userId: string) {
    const userRepo = this.dataSource.getRepository(User);

    const user = await userRepo.findOne({
      where: { id: userId },
      relations: { sportsProfiles: true },
    });

    if (!user) {
      throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
    }

    // 활성 스포츠 프로필만 필터링
    const activeSportsProfiles = user.sportsProfiles
      .filter((p) => p.isActive)
      .map((p) => {
        const isPlacement = p.isPlacement ?? true;
        const placementGamesRemaining = Math.max(0, 5 - (p.gamesPlayed ?? 0));
        // displayScore: 사용자에게 보이는 점수 (glickoRating + activityBonus)
        // 배치 게임 중에는 비공개. glickoRating은 내부 MMR이므로 API에서 노출하지 않음
        const visibleScore = isPlacement ? null : (p.displayScore ?? p.currentScore);
        return {
          id: p.id,
          sportType: p.sportType,
          displayName: p.displayName,
          currentScore: visibleScore,
          displayScore: visibleScore,
          tier: isPlacement ? null : p.tier,
          tierInfo: isPlacement ? null : getTierInfo(p.displayScore ?? p.currentScore),
          gHandicap: p.gHandicap,
          gamesPlayed: p.gamesPlayed,
          wins: p.wins,
          losses: p.losses,
          draws: p.draws,
          isVerified: p.isVerified,
          winStreak: p.winStreak,
          noShowCount: p.noShowCount,
          matchBanUntil: p.matchBanUntil,
          isPlacement,
          placementGamesRemaining,
        };
      });

    // 위치 정보 조회 (raw SQL for PostGIS)
    const locationRows = await this.dataSource.query<
      Array<{
        homeAddress: string | null;
        matchRadiusKm: number;
        homePointLat: number | null;
        homePointLng: number | null;
      }>
    >(
      `SELECT
        home_address AS "homeAddress",
        match_radius_km AS "matchRadiusKm",
        ST_Y(home_point::geography::geometry) AS "homePointLat",
        ST_X(home_point::geography::geometry) AS "homePointLng"
      FROM user_locations
      WHERE user_id = $1::uuid
      LIMIT 1`,
      [userId],
    );

    const location = locationRows[0] ?? null;

    return {
      id: user.id,
      email: user.email,
      nickname: user.nickname,
      profileImageUrl: user.profileImageUrl,
      phone: user.phone,
      gender: user.gender,
      birthDate: user.birthDate,
      status: user.status,
      createdAt: user.createdAt,
      lastLoginAt: user.lastLoginAt,
      preferredSportType: user.preferredSportType,
      sportsProfiles: activeSportsProfiles,
      location: location
        ? {
            homeAddress: location.homeAddress,
            matchRadiusKm: location.matchRadiusKm,
            homePoint: location.homePointLat != null
              ? { lat: location.homePointLat, lng: location.homePointLng }
              : null,
          }
        : null,
    };
  }

  // ─────────────────────────────────────
  // 내 정보 수정
  // ─────────────────────────────────────

  async updateMe(userId: string, dto: UpdateUserDto) {
    const userRepo = this.dataSource.getRepository(User);

    // 닉네임 중복 확인
    if (dto.nickname) {
      const existing = await this.dataSource.query<Array<{ id: string }>>(
        `SELECT id FROM users WHERE nickname = $1 AND id != $2 LIMIT 1`,
        [dto.nickname, userId],
      );
      if (existing.length > 0) {
        throw AppError.conflict(ErrorCode.USER_NICKNAME_TAKEN);
      }
    }

    await userRepo.update(userId, {
      ...(dto.nickname && { nickname: dto.nickname }),
      ...(dto.profileImageUrl && { profileImageUrl: dto.profileImageUrl }),
      ...(dto.phone && { phone: dto.phone }),
      ...(dto.gender && { gender: dto.gender }),
      ...(dto.birthDate && { birthDate: new Date(dto.birthDate) }),
      ...(dto.preferredSportType !== undefined && { preferredSportType: dto.preferredSportType }),
    });

    const updated = await userRepo.findOne({
      where: { id: userId },
      relations: { sportsProfiles: true },
    });

    return updated;
  }

  // ─────────────────────────────────────
  // 활동 지역 설정
  // ─────────────────────────────────────

  async updateLocation(userId: string, dto: UpdateLocationDto) {
    await updateUserHomeLocation(
      userId,
      dto.latitude,
      dto.longitude,
      dto.address,
      dto.matchRadiusKm,
    );

    return {
      latitude: dto.latitude,
      longitude: dto.longitude,
      address: dto.address,
      matchRadiusKm: dto.matchRadiusKm,
    };
  }

  // ─────────────────────────────────────
  // 타 사용자 프로필 조회 (공개 정보)
  // ─────────────────────────────────────

  async getUsersByIds(ids: string[]) {
    if (ids.length === 0) return [];

    const userRepo = this.dataSource.getRepository(User);
    const users = await userRepo
      .createQueryBuilder('user')
      .where('user.id IN (:...ids)', { ids })
      .andWhere('user.status = :status', { status: UserStatus.ACTIVE })
      .select([
        'user.id',
        'user.nickname',
        'user.profileImageUrl',
        'user.status',
        'user.createdAt',
      ])
      .getMany();

    return users.map((u) => ({
      id: u.id,
      nickname: u.nickname,
      profileImageUrl: u.profileImageUrl,
      status: u.status,
      createdAt: u.createdAt,
    }));
  }

  async getUserProfile(targetUserId: string, requestUserId?: string) {
    const userRepo = this.dataSource.getRepository(User);

    const user = await userRepo.findOne({
      where: { id: targetUserId },
      relations: { sportsProfiles: true },
    });

    if (!user || user.status !== 'ACTIVE') {
      throw AppError.notFound(ErrorCode.USER_NOT_FOUND);
    }

    // 활성 스포츠 프로필만 필터링
    const activeSportsProfiles = user.sportsProfiles
      .filter((p) => p.isActive)
      .map((p) => {
        const isPlacement = p.isPlacement ?? true;
        const placementGamesRemaining = Math.max(0, 5 - (p.gamesPlayed ?? 0));
        // displayScore: 사용자에게 보이는 점수 (glickoRating + activityBonus)
        // 배치 게임 중에는 비공개. glickoRating은 내부 MMR이므로 API에서 노출하지 않음
        const visibleScore = isPlacement ? null : (p.displayScore ?? p.currentScore);
        return {
          id: p.id,
          sportType: p.sportType,
          displayName: p.displayName,
          currentScore: visibleScore,
          displayScore: visibleScore,
          tier: isPlacement ? null : p.tier,
          tierInfo: isPlacement ? null : getTierInfo(p.displayScore ?? p.currentScore),
          gHandicap: p.gHandicap,
          gamesPlayed: p.gamesPlayed,
          wins: p.wins,
          losses: p.losses,
          draws: p.draws,
          isVerified: p.isVerified,
          isPlacement,
          placementGamesRemaining,
        };
      });

    // 최근 경기 기록 (최대 5건) — 중첩 관계 조건을 QueryBuilder로 처리
    const gameRepo = this.dataSource.getRepository(Game);
    const recentGames = await gameRepo
      .createQueryBuilder('game')
      .leftJoinAndSelect('game.match', 'match')
      .leftJoinAndSelect('match.requesterProfile', 'requesterProfile')
      .leftJoinAndSelect('requesterProfile.user', 'requesterUser')
      .leftJoinAndSelect('match.opponentProfile', 'opponentProfile')
      .leftJoinAndSelect('opponentProfile.user', 'opponentUser')
      .where('game.resultStatus = :status', { status: 'VERIFIED' })
      .andWhere(
        '(requesterProfile.userId = :userId OR opponentProfile.userId = :userId)',
        { userId: targetUserId },
      )
      .orderBy('game.verifiedAt', 'DESC')
      .take(5)
      .getMany();

    // requesterUser/opponentUser의 select 필드를 응답에서 제한
    const formattedRecentGames = recentGames.map((game) => ({
      ...game,
      match: game.match
        ? {
            ...game.match,
            requesterProfile: game.match.requesterProfile
              ? {
                  ...game.match.requesterProfile,
                  user: game.match.requesterProfile.user
                    ? {
                        nickname: game.match.requesterProfile.user.nickname,
                        profileImageUrl: game.match.requesterProfile.user.profileImageUrl,
                      }
                    : undefined,
                }
              : undefined,
            opponentProfile: game.match.opponentProfile
              ? {
                  ...game.match.opponentProfile,
                  user: game.match.opponentProfile.user
                    ? {
                        nickname: game.match.opponentProfile.user.nickname,
                        profileImageUrl: game.match.opponentProfile.user.profileImageUrl,
                      }
                    : undefined,
                }
              : undefined,
          }
        : undefined,
    }));

    return {
      id: user.id,
      nickname: user.nickname,
      profileImageUrl: user.profileImageUrl,
      status: user.status,
      createdAt: user.createdAt,
      sportsProfiles: activeSportsProfiles,
      recentGames: formattedRecentGames,
    };
  }

  // ─────────────────────────────────────
  // 회원 탈퇴
  // ─────────────────────────────────────

  async deleteMe(userId: string): Promise<void> {
    const userRepo = this.dataSource.getRepository(User);
    await userRepo.update(userId, {
      status: UserStatus.WITHDRAWN,
      email: null,
      phone: null,
      nickname: `탈퇴회원_${Date.now()}`,
    });
  }
}
