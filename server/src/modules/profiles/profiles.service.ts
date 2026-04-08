import { DataSource } from 'typeorm';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { gHandicapToInitialScore, calculateTier, getTierInfo } from '../../shared/utils/elo.js';
import { SportsProfile, ScoreHistory, SportType, Tier, ScoreChangeType } from '../../entities/index.js';
import type {
  CreateSportsProfileDto,
  UpdateSportsProfileDto,
} from './profiles.schema.js';

export class ProfilesService {
  constructor(private dataSource: DataSource) {}

  // ─────────────────────────────────────
  // 스포츠 프로필 생성
  // ─────────────────────────────────────

  async createProfile(userId: string, dto: CreateSportsProfileDto) {
    const profileRepo = this.dataSource.getRepository(SportsProfile);

    // 동일 종목 프로필 중복 확인
    const existing = await profileRepo.findOne({
      where: { userId, sportType: dto.sportType, isActive: true },
    });

    if (existing) {
      throw AppError.conflict(
        ErrorCode.PROFILE_ALREADY_EXISTS,
        `${dto.sportType} 종목의 프로필이 이미 존재합니다.`,
      );
    }

    // G핸디 → ELO 초기 점수 변환 (골프 전용)
    let initialScore = 1000;
    if (dto.sportType === SportType.GOLF && dto.gHandicap !== undefined) {
      initialScore = gHandicapToInitialScore(dto.gHandicap);
    }

    const tier: Tier = calculateTier(initialScore);

    const scoreHistoryRepo = this.dataSource.getRepository(ScoreHistory);

    const now = new Date();
    const profile = await profileRepo.save(
      profileRepo.create({
        userId,
        sportType: dto.sportType,
        displayName: dto.displayName,
        matchMessage: dto.matchMessage ?? null,
        gHandicap: dto.gHandicap !== undefined ? dto.gHandicap : null,
        initialScore,
        currentScore: initialScore,
        tier,
        extraData: dto.extraData ?? {},
        updatedAt: now,
      }),
    );

    // 초기 점수 히스토리 기록
    await scoreHistoryRepo.save(
      scoreHistoryRepo.create({
        sportsProfileId: profile.id,
        changeType: ScoreChangeType.INITIAL,
        scoreBefore: 0,
        scoreChange: initialScore,
        scoreAfter: initialScore,
      }),
    );

    const isPlacement = profile.isPlacement ?? true;
    const placementGamesRemaining = Math.max(0, 5 - (profile.gamesPlayed ?? 0));
    // displayScore: 사용자에게 보이는 점수. 배치 중에는 비공개
    const visibleScore = isPlacement ? null : (profile.displayScore ?? profile.currentScore);

    return {
      id: profile.id,
      sportType: profile.sportType,
      displayName: profile.displayName,
      matchMessage: profile.matchMessage,
      initialScore: profile.initialScore,
      currentScore: visibleScore,
      displayScore: visibleScore,
      tier: isPlacement ? null : profile.tier,
      tierInfo: isPlacement ? null : getTierInfo(profile.displayScore ?? profile.currentScore),
      gHandicap: profile.gHandicap,
      gamesPlayed: profile.gamesPlayed,
      wins: profile.wins,
      losses: profile.losses,
      draws: profile.draws,
      isVerified: profile.isVerified,
      winStreak: profile.winStreak,
      noShowCount: profile.noShowCount,
      matchBanUntil: profile.matchBanUntil,
      isPlacement,
      placementGamesRemaining,
      createdAt: profile.createdAt,
    };
  }

  // ─────────────────────────────────────
  // 스포츠 프로필 목록 조회
  // ─────────────────────────────────────

  async getProfiles(userId: string) {
    const profileRepo = this.dataSource.getRepository(SportsProfile);

    const profiles = await profileRepo.find({
      where: { userId, isActive: true },
      order: { createdAt: 'ASC' },
    });

    // 각 프로필에 tierInfo + 배치 게임 정보 추가
    return profiles.map((p) => {
      const isPlacement = p.isPlacement ?? true;
      const placementGamesRemaining = Math.max(0, 5 - (p.gamesPlayed ?? 0));
      const visibleScore = isPlacement ? null : (p.displayScore ?? p.currentScore);
      return {
        ...p,
        // 배치 게임 중에는 점수 비공개. glickoRating은 내부 MMR이므로 API에서 제거
        glickoRating: undefined,
        glickoRd: undefined,
        glickoVolatility: undefined,
        currentScore: visibleScore,
        displayScore: visibleScore,
        tier: isPlacement ? null : p.tier,
        tierInfo: isPlacement ? null : getTierInfo(p.displayScore ?? p.currentScore),
        isPlacement,
        placementGamesRemaining,
      };
    });
  }

  // ─────────────────────────────────────
  // 스포츠 프로필 수정
  // ─────────────────────────────────────

  async updateProfile(userId: string, profileId: string, dto: UpdateSportsProfileDto) {
    const profileRepo = this.dataSource.getRepository(SportsProfile);

    const profile = await profileRepo.findOne({
      where: { id: profileId, userId, isActive: true },
    });

    if (!profile) {
      throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
    }

    // G핸디 변경 시 점수 재조정 여부 확인
    // 이미 게임을 한 경우엔 G핸디만 업데이트 (ELO 변경 없음)
    let updateData: Record<string, unknown> = {};

    if (dto.displayName) updateData.displayName = dto.displayName;
    if (dto.matchMessage !== undefined) updateData.matchMessage = dto.matchMessage || null;
    if (dto.extraData) updateData.extraData = dto.extraData;

    if (
      dto.gHandicap !== undefined &&
      profile.sportType === SportType.GOLF
    ) {
      updateData.gHandicap = dto.gHandicap;

      // 아직 게임을 하지 않았다면 초기 점수 재계산
      if (profile.gamesPlayed === 0) {
        const newScore = gHandicapToInitialScore(dto.gHandicap);
        const newTier = calculateTier(newScore);
        updateData.initialScore = newScore;
        updateData.currentScore = newScore;
        updateData.tier = newTier;
      }
    }

    await profileRepo.update(profileId, updateData);

    const updated = await profileRepo.findOne({ where: { id: profileId } });
    if (!updated) return null;

    const isPlacement = updated.isPlacement ?? true;
    const placementGamesRemaining = Math.max(0, 5 - (updated.gamesPlayed ?? 0));
    const visibleScore = isPlacement ? null : (updated.displayScore ?? updated.currentScore);

    return {
      ...updated,
      glickoRating: undefined,
      glickoRd: undefined,
      glickoVolatility: undefined,
      currentScore: visibleScore,
      displayScore: visibleScore,
      tier: isPlacement ? null : updated.tier,
      tierInfo: isPlacement ? null : getTierInfo(updated.displayScore ?? updated.currentScore),
      isPlacement,
      placementGamesRemaining,
    };
  }

  // ─────────────────────────────────────
  // 점수 히스토리 조회
  // ─────────────────────────────────────

  async getScoreHistory(userId: string, profileId: string, limit = 20) {
    const profileRepo = this.dataSource.getRepository(SportsProfile);
    const scoreHistoryRepo = this.dataSource.getRepository(ScoreHistory);

    const profile = await profileRepo.findOne({
      where: { id: profileId, userId },
    });

    if (!profile) {
      throw AppError.notFound(ErrorCode.PROFILE_NOT_FOUND);
    }

    const histories = await scoreHistoryRepo.find({
      where: { sportsProfileId: profileId },
      order: { createdAt: 'DESC' },
      take: limit,
    });

    return histories;
  }
}
