import { AppDataSource } from '../../config/database.js';
import {
  Team,
  TeamMember,
  TeamMatchRequest,
  TeamMatch,
  TeamChatRoom,
  TeamChatRoomMember,
  TeamChatMessage,
  TeamPost,
  TeamPostComment,
} from '../../entities/index.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import { wktPoint } from '../../shared/utils/geo.js';
import type {
  CreateTeamDto,
  UpdateTeamDto,
  ChangeRoleDto,
  CreateTeamMatchRequestDto,
  SubmitTeamResultDto,
  CreateTeamPostDto,
  UpdateTeamPostDto,
  CreateTeamPostCommentDto,
  SearchTeamsQuery,
  NearbyTeamsQuery,
  ListTeamPostsQuery,
  GetTeamMessagesQuery,
} from './teams.schema.js';

// ─────────────────────────────────────
// 내부 헬퍼
// ─────────────────────────────────────

function generateSlug(name: string): string {
  // 한글을 포함한 팀명을 slug로 변환
  // 영문+숫자는 소문자로, 그 외는 그대로 + 타임스탬프 suffix
  const base = name
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9가-힣-]/g, '')
    .slice(0, 30);
  const suffix = Date.now().toString(36).slice(-6);
  return `${base}-${suffix}`;
}

export class TeamsService {
  // ─────────────────────────────────────
  // 팀 생성
  // ─────────────────────────────────────

  async createTeam(userId: string, dto: CreateTeamDto) {
    const slug = generateSlug(dto.name);

    // 트랜잭션: 팀 생성 + 생성자를 CAPTAIN으로 등록
    const result = await AppDataSource.transaction(async (manager) => {
      let teamId: string;

      if (dto.latitude !== undefined && dto.longitude !== undefined) {
        // homePoint는 PostGIS raw SQL로 처리
        const pointWkt = wktPoint(dto.latitude, dto.longitude);
        const rows = await manager.query<Array<{ id: string }>>(
          `INSERT INTO teams (
            name, slug, sport_type, logo_url, description,
            home_pin_id, home_point, activity_region,
            min_members, max_members, current_members, is_recruiting, status
          ) VALUES (
            $1, $2, $3::"SportType", $4, $5,
            $6::uuid, ST_GeogFromText($7), $8,
            $9, $10, 1, TRUE, 'ACTIVE'::"TeamStatus"
          )
          RETURNING id`,
          [
            dto.name,
            slug,
            dto.sportType,
            dto.logoUrl ?? null,
            dto.description ?? null,
            dto.homePinId ?? null,
            pointWkt,
            dto.activityRegion ?? null,
            dto.minMembers,
            dto.maxMembers,
          ],
        );
        teamId = rows[0].id;
      } else {
        const teamRepo = manager.getRepository(Team);
        const team = teamRepo.create({
          name: dto.name,
          slug,
          sportType: dto.sportType as any,
          logoUrl: dto.logoUrl ?? null,
          description: dto.description ?? null,
          homePinId: dto.homePinId ?? null,
          activityRegion: dto.activityRegion ?? null,
          minMembers: dto.minMembers,
          maxMembers: dto.maxMembers,
          currentMembers: 1,
        });
        const saved = await teamRepo.save(team);
        teamId = saved.id;
      }

      // 생성자를 CAPTAIN으로 등록
      const memberRepo = manager.getRepository(TeamMember);
      const member = memberRepo.create({
        teamId,
        userId,
        role: 'CAPTAIN' as any,
        status: 'ACTIVE' as any,
        joinedAt: new Date(),
      });
      await memberRepo.save(member);

      const teamRepo = manager.getRepository(Team);
      return teamRepo.findOne({ where: { id: teamId } });
    });

    return result;
  }

  // ─────────────────────────────────────
  // 팀 상세 조회
  // ─────────────────────────────────────

  async getTeam(teamId: string) {
    const teamRepo = AppDataSource.getRepository(Team);
    const team = await teamRepo.findOne({ where: { id: teamId } });

    if (!team) {
      throw AppError.notFound(ErrorCode.TEAM_NOT_FOUND);
    }

    if (team.status === 'DISBANDED' as any) {
      throw AppError.badRequest(ErrorCode.TEAM_DISBANDED);
    }

    // 활성 멤버 조회 (role + joinedAt 정렬)
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const members = await memberRepo
      .createQueryBuilder('member')
      .leftJoinAndSelect('member.user', 'user')
      .where('member.teamId = :teamId', { teamId })
      .andWhere('member.status = :status', { status: 'ACTIVE' })
      .orderBy("CASE member.role WHEN 'CAPTAIN' THEN 0 WHEN 'VICE_CAPTAIN' THEN 1 ELSE 2 END", 'ASC')
      .addOrderBy('member.joinedAt', 'ASC')
      .getMany();

    return { ...team, members };
  }

  // ─────────────────────────────────────
  // 팀 수정 (CAPTAIN만)
  // ─────────────────────────────────────

  async updateTeam(userId: string, teamId: string, dto: UpdateTeamDto) {
    await this.assertCaptain(userId, teamId);

    // homePoint 업데이트가 필요한 경우 raw SQL
    if (dto.latitude !== undefined && dto.longitude !== undefined) {
      const pointWkt = wktPoint(dto.latitude, dto.longitude);
      await AppDataSource.query(
        `UPDATE teams SET home_point = ST_GeogFromText($1), updated_at = NOW() WHERE id = $2::uuid`,
        [pointWkt, teamId],
      );
    }

    const updateData: Partial<Team> = {};
    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.logoUrl !== undefined) updateData.logoUrl = dto.logoUrl ?? null;
    if (dto.description !== undefined) updateData.description = dto.description ?? null;
    if (dto.homePinId !== undefined) updateData.homePinId = dto.homePinId ?? null;
    if (dto.activityRegion !== undefined) updateData.activityRegion = dto.activityRegion ?? null;
    if (dto.minMembers !== undefined) updateData.minMembers = dto.minMembers;
    if (dto.maxMembers !== undefined) updateData.maxMembers = dto.maxMembers;
    if (dto.isRecruiting !== undefined) updateData.isRecruiting = dto.isRecruiting;

    const teamRepo = AppDataSource.getRepository(Team);
    await teamRepo.update(teamId, updateData);

    return teamRepo.findOne({ where: { id: teamId } });
  }

  // ─────────────────────────────────────
  // 팀 해산 (CAPTAIN만)
  // ─────────────────────────────────────

  async disbandTeam(userId: string, teamId: string) {
    await this.assertCaptain(userId, teamId);

    const teamRepo = AppDataSource.getRepository(Team);
    await teamRepo.update(teamId, { status: 'DISBANDED' as any, isRecruiting: false });
  }

  // ─────────────────────────────────────
  // 팀 검색
  // ─────────────────────────────────────

  async searchTeams(query: SearchTeamsQuery) {
    const { q, sportType, cursor, limit } = query;

    const teamRepo = AppDataSource.getRepository(Team);
    const qb = teamRepo
      .createQueryBuilder('team')
      .select([
        'team.id',
        'team.name',
        'team.slug',
        'team.sportType',
        'team.logoUrl',
        'team.activityRegion',
        'team.currentMembers',
        'team.maxMembers',
        'team.wins',
        'team.losses',
        'team.draws',
        'team.teamScore',
        'team.isRecruiting',
        'team.status',
        'team.createdAt',
      ])
      .where('team.status = :status', { status: 'ACTIVE' });

    if (q) {
      qb.andWhere(
        '(team.name ILIKE :q OR team.activityRegion ILIKE :q)',
        { q: `%${q}%` },
      );
    }
    if (sportType) {
      qb.andWhere('team.sportType = :sportType', { sportType });
    }
    if (cursor) {
      qb.andWhere('team.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const teams = await qb
      .orderBy('team.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = teams.length > limit;
    const items = hasMore ? teams.slice(0, limit) : teams;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 주변 팀 조회 (PostGIS)
  // ─────────────────────────────────────

  async getNearbyTeams(query: NearbyTeamsQuery) {
    const { lat, lng, radiusKm, sportType } = query;
    const pointWkt = wktPoint(lat, lng);
    const radiusMeters = radiusKm * 1000;

    type NearbyTeamRow = {
      id: string;
      name: string;
      slug: string;
      sport_type: string;
      logo_url: string | null;
      activity_region: string | null;
      current_members: number;
      max_members: number;
      wins: number;
      losses: number;
      draws: number;
      team_score: number;
      is_recruiting: boolean;
      distance_meters: number;
    };

    let queryStr: string;
    let queryParams: (string | number)[];

    if (sportType) {
      queryStr = `SELECT
        id,
        name,
        slug,
        sport_type,
        logo_url,
        activity_region,
        current_members,
        max_members,
        wins,
        losses,
        draws,
        team_score,
        is_recruiting,
        ST_Distance(home_point, ST_GeogFromText($1)) AS distance_meters
      FROM teams
      WHERE status = 'ACTIVE'::"TeamStatus"
        AND home_point IS NOT NULL
        AND ST_DWithin(home_point, ST_GeogFromText($1), $2)
        AND sport_type = $3::"SportType"
      ORDER BY distance_meters ASC
      LIMIT 50`;
      queryParams = [pointWkt, radiusMeters, sportType];
    } else {
      queryStr = `SELECT
        id,
        name,
        slug,
        sport_type,
        logo_url,
        activity_region,
        current_members,
        max_members,
        wins,
        losses,
        draws,
        team_score,
        is_recruiting,
        ST_Distance(home_point, ST_GeogFromText($1)) AS distance_meters
      FROM teams
      WHERE status = 'ACTIVE'::"TeamStatus"
        AND home_point IS NOT NULL
        AND ST_DWithin(home_point, ST_GeogFromText($1), $2)
      ORDER BY distance_meters ASC
      LIMIT 50`;
      queryParams = [pointWkt, radiusMeters];
    }

    const rows = await AppDataSource.query<NearbyTeamRow[]>(queryStr, queryParams);

    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      slug: r.slug,
      sportType: r.sport_type,
      logoUrl: r.logo_url,
      activityRegion: r.activity_region,
      currentMembers: r.current_members,
      maxMembers: r.max_members,
      wins: r.wins,
      losses: r.losses,
      draws: r.draws,
      teamScore: r.team_score,
      isRecruiting: r.is_recruiting,
      distanceMeters: r.distance_meters,
    }));
  }

  // ─────────────────────────────────────
  // 팀원 목록 조회
  // ─────────────────────────────────────

  async getTeamMembers(teamId: string) {
    await this.assertTeamExists(teamId);

    const memberRepo = AppDataSource.getRepository(TeamMember);
    return memberRepo.find({
      where: { teamId, status: 'ACTIVE' as any },
      relations: ['user'],
      order: { role: 'ASC', joinedAt: 'ASC' },
    });
  }

  // ─────────────────────────────────────
  // 팀 가입 신청
  // ─────────────────────────────────────

  async joinTeam(userId: string, teamId: string) {
    const team = await this.assertTeamExists(teamId);

    if (team.status === 'DISBANDED' as any) {
      throw AppError.badRequest(ErrorCode.TEAM_DISBANDED);
    }

    if (!team.isRecruiting) {
      throw AppError.badRequest(ErrorCode.TEAM_FULL, '현재 팀원을 모집하고 있지 않습니다.');
    }

    if (team.currentMembers >= team.maxMembers) {
      throw AppError.badRequest(ErrorCode.TEAM_FULL);
    }

    // 이미 멤버인지 확인 (BANNED 포함)
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const existing = await memberRepo.findOne({
      where: { teamId, userId },
    });

    if (existing) {
      if (existing.status === 'BANNED' as any) {
        throw AppError.forbidden(ErrorCode.TEAM_NOT_MEMBER, '팀에서 추방된 사용자입니다.');
      }
      throw AppError.conflict(ErrorCode.TEAM_ALREADY_MEMBER);
    }

    const member = await AppDataSource.transaction(async (manager) => {
      const mRepo = manager.getRepository(TeamMember);
      const m = mRepo.create({
        teamId,
        userId,
        role: 'MEMBER' as any,
        status: 'ACTIVE' as any,
        joinedAt: new Date(),
      });
      await mRepo.save(m);

      await manager.getRepository(Team).update(teamId, {
        currentMembers: () => 'current_members + 1',
      } as any);

      return mRepo.findOne({
        where: { id: m.id },
        relations: ['user'],
      });
    });

    return member;
  }

  // ─────────────────────────────────────
  // 팀원 추방 (CAPTAIN만)
  // ─────────────────────────────────────

  async kickMember(captainUserId: string, teamId: string, targetUserId: string) {
    await this.assertCaptain(captainUserId, teamId);

    if (captainUserId === targetUserId) {
      throw AppError.badRequest(ErrorCode.TEAM_NOT_CAPTAIN, '자기 자신을 추방할 수 없습니다. 탈퇴 API를 사용해 주세요.');
    }

    const memberRepo = AppDataSource.getRepository(TeamMember);
    const targetMember = await memberRepo.findOne({
      where: { teamId, userId: targetUserId },
    });

    if (!targetMember || targetMember.status !== 'ACTIVE' as any) {
      throw AppError.notFound(ErrorCode.TEAM_NOT_MEMBER, '해당 팀원을 찾을 수 없습니다.');
    }

    await AppDataSource.transaction(async (manager) => {
      await manager.getRepository(TeamMember).update(
        { teamId, userId: targetUserId },
        { status: 'BANNED' as any },
      );

      await manager.getRepository(Team).update(teamId, {
        currentMembers: () => 'current_members - 1',
      } as any);
    });
  }

  // ─────────────────────────────────────
  // 역할 변경 (CAPTAIN만)
  // ─────────────────────────────────────

  async changeRole(captainUserId: string, teamId: string, targetUserId: string, dto: ChangeRoleDto) {
    await this.assertCaptain(captainUserId, teamId);

    if (captainUserId === targetUserId) {
      throw AppError.badRequest(
        ErrorCode.TEAM_NOT_CAPTAIN,
        '방장은 자기 자신의 역할을 변경할 수 없습니다. 다른 멤버를 CAPTAIN으로 지정하여 방장을 양도해 주세요.',
      );
    }

    const memberRepo = AppDataSource.getRepository(TeamMember);
    const targetMember = await memberRepo.findOne({
      where: { teamId, userId: targetUserId },
    });

    if (!targetMember || targetMember.status !== 'ACTIVE' as any) {
      throw AppError.notFound(ErrorCode.TEAM_NOT_MEMBER, '해당 팀원을 찾을 수 없습니다.');
    }

    // CAPTAIN 양도: 기존 CAPTAIN → MEMBER, 대상 → CAPTAIN (트랜잭션)
    if (dto.role === 'CAPTAIN' as any) {
      await AppDataSource.transaction(async (manager) => {
        const mRepo = manager.getRepository(TeamMember);
        // 기존 CAPTAIN을 MEMBER로 변경
        await mRepo.update({ teamId, userId: captainUserId }, { role: 'MEMBER' as any });
        // 대상을 CAPTAIN으로 변경
        await mRepo.update({ teamId, userId: targetUserId }, { role: 'CAPTAIN' as any });
      });
    } else {
      // VICE_CAPTAIN 임명/해임 또는 MEMBER로 강등
      await memberRepo.update({ teamId, userId: targetUserId }, { role: dto.role as any });
    }
  }

  // ─────────────────────────────────────
  // 팀 탈퇴
  // ─────────────────────────────────────

  async leaveTeam(userId: string, teamId: string) {
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const member = await memberRepo.findOne({ where: { teamId, userId } });

    if (!member || member.status !== 'ACTIVE' as any) {
      throw AppError.notFound(ErrorCode.TEAM_NOT_MEMBER);
    }

    // CAPTAIN은 반드시 다른 멤버에게 방장을 양도한 후 탈퇴 가능
    if (member.role === 'CAPTAIN' as any) {
      throw AppError.badRequest(
        ErrorCode.TEAM_CAPTAIN_CANNOT_LEAVE,
        '방장은 팀을 탈퇴하기 전에 다른 멤버에게 방장을 양도해야 합니다. 역할 변경 API를 통해 방장을 양도해 주세요.',
      );
    }

    await AppDataSource.transaction(async (manager) => {
      await manager.getRepository(TeamMember).update(
        { teamId, userId },
        { status: 'INACTIVE' as any },
      );

      await manager.getRepository(Team).update(teamId, {
        currentMembers: () => 'current_members - 1',
      } as any);
    });
  }

  // ─────────────────────────────────────
  // 팀 매칭 요청 생성 (CAPTAIN 또는 VICE_CAPTAIN만)
  // ─────────────────────────────────────

  async createTeamMatchRequest(userId: string, teamId: string, dto: CreateTeamMatchRequestDto) {
    await this.assertCaptainOrViceCaptain(userId, teamId);

    const team = await this.assertTeamExists(teamId);

    const expiresAt = dto.desiredDate
      ? new Date(`${dto.desiredDate}T23:59:59Z`)
      : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    let requestId: string;

    if (dto.latitude !== undefined && dto.longitude !== undefined) {
      const pointWkt = wktPoint(dto.latitude, dto.longitude);
      const rows = await AppDataSource.query<Array<{ id: string }>>(
        `INSERT INTO team_match_requests (
          requester_team_id, requested_by, sport_type,
          desired_date, desired_time_slot,
          location_point, location_name,
          radius_km, message, status, expires_at
        ) VALUES (
          $1::uuid, $2::uuid, $3::"SportType",
          $4::date, $5::"TimeSlot",
          ST_GeogFromText($6), $7,
          $8, $9, 'WAITING'::"MatchRequestStatus", $10
        )
        RETURNING id`,
        [
          teamId,
          userId,
          team.sportType,
          dto.desiredDate ? new Date(dto.desiredDate) : null,
          dto.desiredTimeSlot ?? null,
          pointWkt,
          dto.locationName ?? null,
          dto.radiusKm,
          dto.message ?? null,
          expiresAt,
        ],
      );
      requestId = rows[0].id;
    } else {
      const reqRepo = AppDataSource.getRepository(TeamMatchRequest);
      const req = reqRepo.create({
        requesterTeamId: teamId,
        requestedBy: userId,
        sportType: team.sportType,
        desiredDate: dto.desiredDate ? new Date(dto.desiredDate) : null,
        desiredTimeSlot: dto.desiredTimeSlot as any ?? null,
        locationName: dto.locationName ?? null,
        radiusKm: dto.radiusKm,
        message: dto.message ?? null,
        status: 'WAITING' as any,
        expiresAt,
      });
      const saved = await reqRepo.save(req);
      requestId = saved.id;
    }

    return { id: requestId, status: 'WAITING', expiresAt };
  }

  // ─────────────────────────────────────
  // 팀 매칭 요청 취소
  // ─────────────────────────────────────

  async cancelTeamMatchRequest(userId: string, requestId: string) {
    const reqRepo = AppDataSource.getRepository(TeamMatchRequest);
    const req = await reqRepo.findOne({
      where: { id: requestId },
      relations: ['requesterTeam'],
    });

    if (!req) {
      throw AppError.notFound(ErrorCode.TEAM_MATCH_REQUEST_NOT_FOUND);
    }

    await this.assertCaptainOrViceCaptain(userId, req.requesterTeamId);

    if (req.status !== 'WAITING' as any) {
      throw AppError.badRequest(ErrorCode.MATCH_INVALID_STATUS, '대기 중인 요청만 취소할 수 있습니다.');
    }

    await reqRepo.update(requestId, { status: 'CANCELLED' as any });
  }

  // ─────────────────────────────────────
  // 팀 매칭 목록 조회
  // ─────────────────────────────────────

  async getTeamMatches(userId: string, teamId: string) {
    await this.assertTeamMember(userId, teamId);

    const matchRepo = AppDataSource.getRepository(TeamMatch);
    const matches = await matchRepo
      .createQueryBuilder('match')
      .leftJoinAndSelect('match.homeTeam', 'homeTeam')
      .leftJoinAndSelect('match.awayTeam', 'awayTeam')
      .where('match.homeTeamId = :teamId OR match.awayTeamId = :teamId', { teamId })
      .orderBy('match.createdAt', 'DESC')
      .getMany();

    return matches;
  }

  // ─────────────────────────────────────
  // 팀 매칭 상세 조회
  // ─────────────────────────────────────

  async getTeamMatch(userId: string, matchId: string) {
    const matchRepo = AppDataSource.getRepository(TeamMatch);
    const match = await matchRepo.findOne({
      where: { id: matchId },
      relations: ['homeTeam', 'awayTeam'],
    });

    if (!match) {
      throw AppError.notFound(ErrorCode.TEAM_MATCH_NOT_FOUND);
    }

    // 참여 팀 멤버인지 확인
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const isMember =
      (await memberRepo
        .createQueryBuilder('member')
        .where('member.userId = :userId', { userId })
        .andWhere('member.teamId IN (:...teamIds)', { teamIds: [match.homeTeamId, match.awayTeamId] })
        .andWhere('member.status = :status', { status: 'ACTIVE' })
        .getOne()) !== null;

    if (!isMember) {
      throw AppError.forbidden(ErrorCode.TEAM_NOT_MEMBER, '해당 팀 매칭의 참여자가 아닙니다.');
    }

    return match;
  }

  // ─────────────────────────────────────
  // 팀 매칭 확정
  // ─────────────────────────────────────

  async confirmTeamMatch(userId: string, matchId: string) {
    const matchRepo = AppDataSource.getRepository(TeamMatch);
    const match = await matchRepo.findOne({ where: { id: matchId } });

    if (!match) {
      throw AppError.notFound(ErrorCode.TEAM_MATCH_NOT_FOUND);
    }

    // homeTeam 또는 awayTeam 중 하나의 CAPTAIN/VICE_CAPTAIN이면 허용
    const isHomeLeader = await this.isTeamLeader(userId, match.homeTeamId);
    const isAwayLeader = await this.isTeamLeader(userId, match.awayTeamId);

    if (!isHomeLeader && !isAwayLeader) {
      throw AppError.forbidden(ErrorCode.TEAM_INSUFFICIENT_PERMISSION, '해당 팀 매칭의 CAPTAIN 또는 VICE_CAPTAIN만 확정할 수 있습니다.');
    }

    if (match.status !== 'CHAT' as any) {
      throw AppError.badRequest(ErrorCode.MATCH_INVALID_STATUS, '채팅 상태에서만 확정할 수 있습니다.');
    }

    await matchRepo.update(matchId, { status: 'CONFIRMED' as any, confirmedAt: new Date() });

    return matchRepo.findOne({ where: { id: matchId } });
  }

  // ─────────────────────────────────────
  // 팀 경기 결과 입력 (CAPTAIN 또는 VICE_CAPTAIN만)
  // ─────────────────────────────────────

  async submitTeamResult(userId: string, matchId: string, dto: SubmitTeamResultDto) {
    const matchRepo = AppDataSource.getRepository(TeamMatch);
    const match = await matchRepo.findOne({ where: { id: matchId } });

    if (!match) {
      throw AppError.notFound(ErrorCode.TEAM_MATCH_NOT_FOUND);
    }

    // 양 팀 중 하나의 CAPTAIN/VICE_CAPTAIN 확인
    const isHomeLeader = await this.isTeamLeader(userId, match.homeTeamId);
    const isAwayLeader = await this.isTeamLeader(userId, match.awayTeamId);

    if (!isHomeLeader && !isAwayLeader) {
      throw AppError.forbidden(ErrorCode.TEAM_INSUFFICIENT_PERMISSION);
    }

    if (match.status !== 'CONFIRMED' as any && match.status !== 'CHAT' as any) {
      throw AppError.badRequest(ErrorCode.MATCH_INVALID_STATUS, '확정된 경기만 결과를 입력할 수 있습니다.');
    }

    // 승자 결정
    let winnerTeamId: string | null = null;
    if (dto.homeScore > dto.awayScore) {
      winnerTeamId = match.homeTeamId;
    } else if (dto.awayScore > dto.homeScore) {
      winnerTeamId = match.awayTeamId;
    }

    const updateData: Partial<TeamMatch> = {
      homeScore: dto.homeScore,
      awayScore: dto.awayScore,
      winnerTeamId,
      resultStatus: 'PROOF_UPLOADED' as any,
      status: 'COMPLETED' as any,
      completedAt: new Date(),
    };

    if (dto.venueName) updateData.venueName = dto.venueName;

    await AppDataSource.transaction(async (manager) => {
      const mRepo = manager.getRepository(TeamMatch);
      await mRepo.update(matchId, updateData);

      // 팀 전적 업데이트
      const tRepo = manager.getRepository(Team);
      if (winnerTeamId) {
        const loserTeamId = winnerTeamId === match.homeTeamId ? match.awayTeamId : match.homeTeamId;
        await tRepo.update(winnerTeamId, {
          wins: () => 'wins + 1',
          teamScore: () => 'team_score + 25',
        } as any);
        await tRepo.update(loserTeamId, {
          losses: () => 'losses + 1',
          teamScore: () => 'GREATEST(team_score - 15, 0)',
        } as any);
      } else {
        // 무승부
        await tRepo.update(match.homeTeamId, { draws: () => 'draws + 1' } as any);
        await tRepo.update(match.awayTeamId, { draws: () => 'draws + 1' } as any);
      }
    });

    // venueLocation PostGIS 업데이트
    if (dto.venueLatitude !== undefined && dto.venueLongitude !== undefined) {
      const pointWkt = wktPoint(dto.venueLatitude, dto.venueLongitude);
      await AppDataSource.query(
        `UPDATE team_matches SET venue_location = ST_GeogFromText($1) WHERE id = $2::uuid`,
        [pointWkt, matchId],
      );
    }

    return matchRepo.findOne({ where: { id: matchId } });
  }

  // ─────────────────────────────────────
  // 팀 채팅방 목록
  // ─────────────────────────────────────

  async getTeamChatRooms(userId: string) {
    const roomRepo = AppDataSource.getRepository(TeamChatRoom);
    const rooms = await roomRepo
      .createQueryBuilder('room')
      .innerJoin('room.members', 'myMembership', 'myMembership.userId = :userId', { userId })
      .leftJoinAndSelect('room.members', 'member')
      .leftJoinAndSelect('member.user', 'memberUser')
      .leftJoinAndSelect('member.team', 'memberTeam')
      .where('room.status = :status', { status: 'ACTIVE' })
      .orderBy('room.lastMessageAt', 'DESC')
      .getMany();

    return rooms;
  }

  // ─────────────────────────────────────
  // 팀 채팅 메시지 목록
  // ─────────────────────────────────────

  async getTeamChatMessages(userId: string, roomId: string, query: GetTeamMessagesQuery) {
    const { cursor, limit } = query;

    // 채팅방 존재 및 참여 여부 확인
    const roomRepo = AppDataSource.getRepository(TeamChatRoom);
    const room = await roomRepo.findOne({ where: { id: roomId } });

    if (!room) {
      throw AppError.notFound(ErrorCode.TEAM_CHAT_ROOM_NOT_FOUND);
    }

    const memberRoomRepo = AppDataSource.getRepository(TeamChatRoomMember);
    const membership = await memberRoomRepo.findOne({
      where: { teamChatRoomId: roomId, userId },
    });

    if (!membership) {
      throw AppError.forbidden(ErrorCode.CHAT_NOT_PARTICIPANT, '해당 채팅방의 참여자가 아닙니다.');
    }

    const msgRepo = AppDataSource.getRepository(TeamChatMessage);
    const qb = msgRepo
      .createQueryBuilder('msg')
      .leftJoinAndSelect('msg.sender', 'sender')
      .where('msg.teamChatRoomId = :roomId', { roomId });

    if (cursor) {
      qb.andWhere('msg.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const messages = await qb
      .orderBy('msg.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = messages.length > limit;
    const items = hasMore ? messages.slice(0, limit) : messages;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 팀 게시판: 게시글 목록
  // ─────────────────────────────────────

  async getTeamPosts(teamId: string, query: ListTeamPostsQuery) {
    await this.assertTeamExists(teamId);

    const { category, cursor, limit } = query;

    const postRepo = AppDataSource.getRepository(TeamPost);
    const qb = postRepo
      .createQueryBuilder('post')
      .leftJoinAndSelect('post.author', 'author')
      .where('post.teamId = :teamId', { teamId });

    if (category) {
      qb.andWhere('post.category = :category', { category });
    }
    if (cursor) {
      qb.andWhere('post.createdAt < :cursor', { cursor: new Date(cursor) });
    }

    const posts = await qb
      .orderBy('post.isPinned', 'DESC')
      .addOrderBy('post.createdAt', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = posts.length > limit;
    const items = hasMore ? posts.slice(0, limit) : posts;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // 팀 게시판: 게시글 생성
  // ─────────────────────────────────────

  async createTeamPost(userId: string, teamId: string, dto: CreateTeamPostDto) {
    await this.assertTeamMember(userId, teamId);

    // NOTICE 카테고리는 CAPTAIN/VICE_CAPTAIN만
    if (dto.category === 'NOTICE' as any) {
      await this.assertCaptainOrViceCaptain(userId, teamId);
    }

    const postRepo = AppDataSource.getRepository(TeamPost);
    const post = postRepo.create({
      teamId,
      authorId: userId,
      category: dto.category as any,
      title: dto.title,
      content: dto.content,
      isPinned: dto.isPinned ?? false,
    });
    await postRepo.save(post);

    return postRepo.findOne({
      where: { id: post.id },
      relations: ['author'],
    });
  }

  // ─────────────────────────────────────
  // 팀 게시판: 게시글 상세
  // ─────────────────────────────────────

  async getTeamPost(teamId: string, postId: string) {
    const postRepo = AppDataSource.getRepository(TeamPost);
    const post = await postRepo.findOne({
      where: { id: postId, teamId },
      relations: ['author'],
    });

    if (!post) {
      throw AppError.notFound(ErrorCode.TEAM_POST_NOT_FOUND);
    }

    // parentId가 null인 댓글만 (TypeORM에서 null 처리)
    const commentRepo = AppDataSource.getRepository(TeamPostComment);
    const rootComments = await commentRepo
      .createQueryBuilder('comment')
      .leftJoinAndSelect('comment.author', 'author')
      .where('comment.teamPostId = :postId', { postId })
      .andWhere('comment.parentId IS NULL')
      .orderBy('comment.createdAt', 'ASC')
      .getMany();

    // 대댓글 조회
    const replies = await commentRepo
      .createQueryBuilder('reply')
      .leftJoinAndSelect('reply.author', 'author')
      .where('reply.teamPostId = :postId', { postId })
      .andWhere('reply.parentId IS NOT NULL')
      .orderBy('reply.createdAt', 'ASC')
      .getMany();

    // 대댓글을 부모에 붙이기
    const rootCommentsWithReplies = rootComments.map((c) => ({
      ...c,
      replies: replies.filter((r) => r.parentId === c.id),
    }));

    return { ...post, comments: rootCommentsWithReplies };
  }

  // ─────────────────────────────────────
  // 팀 게시판: 게시글 수정
  // ─────────────────────────────────────

  async updateTeamPost(userId: string, teamId: string, postId: string, dto: UpdateTeamPostDto) {
    const postRepo = AppDataSource.getRepository(TeamPost);
    const post = await postRepo.findOne({ where: { id: postId, teamId } });

    if (!post) {
      throw AppError.notFound(ErrorCode.TEAM_POST_NOT_FOUND);
    }

    if (post.authorId !== userId) {
      throw AppError.forbidden(ErrorCode.TEAM_POST_NOT_AUTHOR);
    }

    // isPinned 변경은 CAPTAIN/VICE_CAPTAIN만
    if (dto.isPinned !== undefined) {
      await this.assertCaptainOrViceCaptain(userId, teamId);
    }

    const updateData: Record<string, unknown> = {};
    if (dto.category !== undefined) updateData['category'] = dto.category;
    if (dto.title !== undefined) updateData['title'] = dto.title;
    if (dto.content !== undefined) updateData['content'] = dto.content;
    if (dto.isPinned !== undefined) updateData['isPinned'] = dto.isPinned;

    await postRepo.update(postId, updateData as any);

    return postRepo.findOne({
      where: { id: postId },
      relations: ['author'],
    });
  }

  // ─────────────────────────────────────
  // 팀 게시판: 게시글 삭제
  // ─────────────────────────────────────

  async deleteTeamPost(userId: string, teamId: string, postId: string) {
    const postRepo = AppDataSource.getRepository(TeamPost);
    const post = await postRepo.findOne({ where: { id: postId, teamId } });

    if (!post) {
      throw AppError.notFound(ErrorCode.TEAM_POST_NOT_FOUND);
    }

    // 작성자 또는 CAPTAIN만 삭제 가능
    if (post.authorId !== userId) {
      await this.assertCaptain(userId, teamId);
    }

    await postRepo.delete(postId);
  }

  // ─────────────────────────────────────
  // 팀 게시판: 댓글 생성
  // ─────────────────────────────────────

  async createTeamPostComment(userId: string, teamId: string, postId: string, dto: CreateTeamPostCommentDto) {
    await this.assertTeamMember(userId, teamId);

    const postRepo = AppDataSource.getRepository(TeamPost);
    const post = await postRepo.findOne({ where: { id: postId, teamId } });

    if (!post) {
      throw AppError.notFound(ErrorCode.TEAM_POST_NOT_FOUND);
    }

    // 대댓글 깊이 체크: 부모 댓글이 대댓글이면 더 이상 허용 안 함
    if (dto.parentId) {
      const commentRepo = AppDataSource.getRepository(TeamPostComment);
      const parentComment = await commentRepo.findOne({ where: { id: dto.parentId } });

      if (!parentComment) {
        throw AppError.notFound(ErrorCode.TEAM_COMMENT_NOT_FOUND, '부모 댓글을 찾을 수 없습니다.');
      }

      if (parentComment.parentId) {
        throw AppError.badRequest(ErrorCode.COMMENT_DEPTH_EXCEEDED, '대댓글에는 답글을 달 수 없습니다.');
      }
    }

    const commentRepo = AppDataSource.getRepository(TeamPostComment);
    const comment = commentRepo.create({
      teamPostId: postId,
      authorId: userId,
      parentId: dto.parentId ?? null,
      content: dto.content,
    });
    await commentRepo.save(comment);

    return commentRepo.findOne({
      where: { id: comment.id },
      relations: ['author'],
    });
  }

  // ─────────────────────────────────────
  // 내부 헬퍼 메서드
  // ─────────────────────────────────────

  private async assertTeamExists(teamId: string) {
    const teamRepo = AppDataSource.getRepository(Team);
    const team = await teamRepo.findOne({ where: { id: teamId } });
    if (!team) {
      throw AppError.notFound(ErrorCode.TEAM_NOT_FOUND);
    }
    return team;
  }

  private async assertTeamMember(userId: string, teamId: string) {
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const member = await memberRepo.findOne({ where: { teamId, userId } });

    if (!member || member.status !== 'ACTIVE' as any) {
      throw AppError.forbidden(ErrorCode.TEAM_NOT_MEMBER);
    }

    return member;
  }

  private async assertCaptain(userId: string, teamId: string) {
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const member = await memberRepo.findOne({ where: { teamId, userId } });

    if (!member || member.status !== 'ACTIVE' as any) {
      throw AppError.forbidden(ErrorCode.TEAM_NOT_MEMBER);
    }

    if (member.role !== 'CAPTAIN' as any) {
      throw AppError.forbidden(ErrorCode.TEAM_NOT_CAPTAIN);
    }

    return member;
  }

  private async assertCaptainOrViceCaptain(userId: string, teamId: string) {
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const member = await memberRepo.findOne({ where: { teamId, userId } });

    if (!member || member.status !== 'ACTIVE' as any) {
      throw AppError.forbidden(ErrorCode.TEAM_NOT_MEMBER);
    }

    if (member.role !== 'CAPTAIN' as any && member.role !== 'VICE_CAPTAIN' as any) {
      throw AppError.forbidden(ErrorCode.TEAM_INSUFFICIENT_PERMISSION);
    }

    return member;
  }

  private async isTeamLeader(userId: string, teamId: string): Promise<boolean> {
    const memberRepo = AppDataSource.getRepository(TeamMember);
    const member = await memberRepo.findOne({ where: { teamId, userId } });
    return !!(
      member &&
      member.status === 'ACTIVE' as any &&
      (member.role === 'CAPTAIN' as any || member.role === 'VICE_CAPTAIN' as any)
    );
  }
}
