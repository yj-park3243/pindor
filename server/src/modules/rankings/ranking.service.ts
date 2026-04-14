import { Redis } from 'ioredis';
import { In } from 'typeorm';
import { AppDataSource } from '../../config/database.js';
import {
  SportType,
  Pin,
  SportsProfile,
  RankingEntry,
  UserPin,
} from '../../entities/index.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { RankingCache } from './ranking.cache.js';
import { calculateTierByRank } from '../../shared/utils/elo.js';

export class RankingService {
  private cache: RankingCache;

  constructor(redis: Redis) {
    this.cache = new RankingCache(redis);
  }

  // ─────────────────────────────────────
  // 핀 랭킹 조회
  // ─────────────────────────────────────

  async getPinRanking(
    pinId: string,
    sportType: SportType,
    limit: number,
    requestUserId?: string,
  ) {
    const pinRepo = AppDataSource.getRepository(Pin);
    const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);
    const rankingEntryRepo = AppDataSource.getRepository(RankingEntry);

    // 핀 존재 확인
    const pin = await pinRepo.findOne({ where: { id: pinId } });

    if (!pin) {
      throw AppError.notFound(ErrorCode.PIN_NOT_FOUND);
    }

    // Redis 캐시에서 랭킹 조회
    const cachedRanking = await this.cache.getTopRanking(pinId, sportType, limit);

    if (cachedRanking.length > 0) {
      // 캐시 히트 — 사용자 상세 정보 조회
      const profileIds = cachedRanking.map((r) => r.sportsProfileId);
      const profiles = await sportsProfileRepo.find({
        where: { id: In(profileIds) },
        relations: ['user'],
      });

      const profileMap = new Map(profiles.map((p) => [p.id, p]));

      const rankings = cachedRanking.map((r) => {
        const profile = profileMap.get(r.sportsProfileId);
        if (!profile) return null;

        return {
          rank: r.rank,
          sportsProfile: {
            id: profile.id,
            userId: profile.userId,
            nickname: profile.user.nickname,
            profileImageUrl: profile.user.profileImageUrl,
            tier: profile.tier,
            score: r.score,
            gamesPlayed: profile.gamesPlayed,
          },
        };
      }).filter(Boolean);

      // 내 랭킹 조회
      let myRank = null;
      if (requestUserId) {
        const userProfile = await sportsProfileRepo.findOne({
          where: { userId: requestUserId, sportType, isActive: true },
        });

        if (userProfile) {
          const myRankData = await this.cache.getUserRank(
            pinId,
            sportType,
            userProfile.id,
          );
          if (myRankData.rank !== null) {
            // DB에서 정확한 tier 조회 (등수 기반으로 계산된 값)
            const dbEntry = await rankingEntryRepo.findOne({
              where: { pinId, sportType: sportType as any, sportsProfileId: userProfile.id },
              select: { tier: true } as any,
            });
            myRank = { rank: myRankData.rank, score: myRankData.score, tier: dbEntry?.tier ?? 'IRON' };
          }
        }
      }

      return {
        pin: {
          id: pin.id,
          name: pin.name,
          level: pin.level,
        },
        rankings,
        myRank,
        fromCache: true,
      };
    }

    // 캐시 미스 — DB에서 조회 후 캐시 빌드
    return this.buildPinRankingFromDb(pin, sportType, limit, requestUserId);
  }

  // ─────────────────────────────────────
  // DB에서 핀 랭킹 빌드
  // ─────────────────────────────────────

  private async buildPinRankingFromDb(
    pin: Pin,
    sportType: SportType,
    limit: number,
    requestUserId?: string,
  ) {
    const rankingEntryRepo = AppDataSource.getRepository(RankingEntry);

    const entries = await rankingEntryRepo.find({
      where: { pinId: pin.id, sportType },
      order: { rank: 'ASC' },
      take: limit,
      relations: ['sportsProfile', 'sportsProfile.user'],
    });

    // Redis 캐시 빌드
    for (const entry of entries) {
      await this.cache.updateScore(pin.id, sportType, entry.sportsProfileId, entry.score);
    }

    const rankings = entries.map((entry) => ({
      rank: entry.rank,
      sportsProfile: {
        id: entry.sportsProfile.id,
        userId: entry.sportsProfile.userId,
        nickname: entry.sportsProfile.user.nickname,
        profileImageUrl: entry.sportsProfile.user.profileImageUrl,
        tier: entry.sportsProfile.tier,
        score: entry.score,
        gamesPlayed: entry.gamesPlayed,
      },
    }));

    let myRank = null;
    if (requestUserId) {
      // sportsProfile.userId = requestUserId 조건으로 조회
      const myEntry = await rankingEntryRepo
        .createQueryBuilder('re')
        .innerJoin('re.sportsProfile', 'sp')
        .where('re.pinId = :pinId', { pinId: pin.id })
        .andWhere('re.sportType = :sportType', { sportType })
        .andWhere('sp.userId = :userId', { userId: requestUserId })
        .getOne();

      if (myEntry) {
        myRank = { rank: myEntry.rank, score: myEntry.score, tier: myEntry.tier };
      }
    }

    return {
      pin: { id: pin.id, name: pin.name, level: pin.level },
      rankings,
      myRank,
      fromCache: false,
    };
  }

  // ─────────────────────────────────────
  // 전국 랭킹
  // ─────────────────────────────────────

  async getNationalRanking(
    sportType: SportType,
    cursor?: string,
    limit = 50,
  ) {
    const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);
    const offset = cursor ? parseInt(cursor, 10) : 0;
    const cachedRanking = await this.cache.getNationalRanking(sportType, offset, limit + 1);

    if (cachedRanking.length > 0) {
      const hasMore = cachedRanking.length > limit;
      const items = hasMore ? cachedRanking.slice(0, limit) : cachedRanking;

      const profileIds = items.map((r) => r.sportsProfileId);
      const profiles = await sportsProfileRepo.find({
        where: { id: In(profileIds) },
        relations: ['user'],
      });

      const profileMap = new Map(profiles.map((p) => [p.id, p]));

      const rankings = items.map((r) => {
        const profile = profileMap.get(r.sportsProfileId);
        if (!profile) return null;

        return {
          rank: r.rank,
          sportsProfile: {
            id: profile.id,
            nickname: profile.user.nickname,
            profileImageUrl: profile.user.profileImageUrl,
            tier: profile.tier,
            score: r.score,
            gamesPlayed: profile.gamesPlayed,
          },
        };
      }).filter(Boolean);

      const nextCursor = hasMore ? String(offset + limit) : null;
      return { rankings, nextCursor, hasMore };
    }

    // DB fallback
    const entries = await sportsProfileRepo
      .createQueryBuilder('sp')
      .innerJoinAndSelect('sp.user', 'u')
      .where('sp.sportType = :sportType', { sportType })
      .andWhere('sp.isActive = true')
      .andWhere('sp.gamesPlayed >= 10')
      .andWhere('u.status = :status', { status: 'ACTIVE' })
      .orderBy('sp.currentScore', 'DESC')
      .skip(offset)
      .take(limit + 1)
      .getMany();

    const hasMore = entries.length > limit;
    const items = hasMore ? entries.slice(0, limit) : entries;

    const rankings = items.map((p, idx) => ({
      rank: offset + idx + 1,
      sportsProfile: {
        id: p.id,
        nickname: p.user.nickname,
        profileImageUrl: p.user.profileImageUrl,
        tier: p.tier,
        score: p.currentScore,
        gamesPlayed: p.gamesPlayed,
      },
    }));

    const nextCursor = hasMore ? String(offset + limit) : null;
    return { rankings, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 등수 기반 티어 일괄 재계산 (ranking_entries 기준)
  // ─────────────────────────────────────

  async recalculateAllTiers(sportType: SportType): Promise<{ updated: number }> {
    const rankingEntryRepo = AppDataSource.getRepository(RankingEntry);
    const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);

    // 모든 핀의 해당 종목 랭킹 엔트리 조회
    const entries = await rankingEntryRepo.find({
      where: { sportType: sportType as any },
      order: { pinId: 'ASC', rank: 'ASC' },
    });

    // 핀별 그룹핑
    const pinGroups = new Map<string, typeof entries>();
    for (const entry of entries) {
      const group = pinGroups.get(entry.pinId) ?? [];
      group.push(entry);
      pinGroups.set(entry.pinId, group);
    }

    let updatedCount = 0;

    for (const [, group] of pinGroups) {
      const totalPlayers = group.length;
      for (const entry of group) {
        const newTier = calculateTierByRank(entry.rank, totalPlayers);
        if (newTier !== entry.tier) {
          await rankingEntryRepo.update(entry.id, { tier: newTier });
          // sports_profiles.tier도 동기화 (대표 핀 기준)
          await sportsProfileRepo.update(entry.sportsProfileId, { tier: newTier });
          updatedCount++;
        }
      }
    }

    return { updated: updatedCount };
  }

  // ─────────────────────────────────────
  // 내 랭킹 조회
  // ─────────────────────────────────────

  async getMyRanking(userId: string, sportType: SportType) {
    const sportsProfileRepo = AppDataSource.getRepository(SportsProfile);
    const userPinRepo = AppDataSource.getRepository(UserPin);
    const rankingEntryRepo2 = AppDataSource.getRepository(RankingEntry);

    const profile = await sportsProfileRepo.findOne({
      where: { userId, sportType, isActive: true },
    });

    if (!profile) {
      throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
    }

    // 내가 속한 핀들의 랭킹 조회
    const userPins = await userPinRepo.find({
      where: { userId },
      relations: ['pin'],
    });

    const rankingEntryRepo = AppDataSource.getRepository(RankingEntry);
    const pinRankings = await Promise.all(
      userPins.map(async (up) => {
        // Redis 캐시 우선 조회
        let rankData = await this.cache.getUserRank(up.pinId, sportType, profile.id);

        // Redis 미스 시 DB fallback
        if (rankData.rank === null) {
          const dbEntry = await rankingEntryRepo.findOne({
            where: { pinId: up.pinId, sportType: sportType as any, sportsProfileId: profile.id },
          });
          if (dbEntry) {
            rankData = { rank: dbEntry.rank, score: dbEntry.score };
            // Redis 캐시에 저장 (다음 조회 시 캐시 히트)
            await this.cache.updateScore(up.pinId, sportType, profile.id, dbEntry.score);
          }
        }

        const entryScore = rankData.score ?? profile.currentScore;
        // DB에서 등수 기반 tier 조회
        const dbTierEntry = await rankingEntryRepo2.findOne({
          where: { pinId: up.pinId, sportType: sportType as any, sportsProfileId: profile.id },
          select: { tier: true } as any,
        });
        const entryTier = dbTierEntry?.tier ?? 'IRON';
        return {
          pin: { id: up.pin.id, name: up.pin.name, level: up.pin.level },
          rank: rankData.rank,
          score: entryScore,
          tier: entryTier,
          isPrimary: up.isPrimary,
        };
      }),
    );

    return {
      profile: {
        id: profile.id,
        sportType: profile.sportType,
        currentScore: profile.currentScore,
        tier: profile.tier,
        gamesPlayed: profile.gamesPlayed,
        wins: profile.wins,
        losses: profile.losses,
        draws: profile.draws,
      },
      pinRankings,
    };
  }
}
