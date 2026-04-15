import { DataSource } from 'typeorm';
import { redis } from '../../config/redis.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';
import {
  calculateBothElo,
  getKFactor,
  calculateTierByRank,
  determineGolfWinner,
} from '../../shared/utils/elo.js';
import { getKSTMidnight } from '../../shared/utils/timezone.js';
import { updateGlicko2 } from '../../shared/utils/glicko2.js';
import type { Glicko2Rating, Glicko2Result } from '../../shared/utils/glicko2.js';
import type {
  SubmitGameResultDto,
  ConfirmGameResultDto,
  DisputeGameResultDto,
  ListGamesQuery,
} from './games.schema.js';
import type { INotificationService, NotificationPayload } from '../../shared/types/index.js';
import {
  Game,
  Match,
  MatchRequest,
  SportsProfile,
  ResultConfirmation,
  ScoreHistory,
  RankingEntry,
} from '../../entities/index.js';
import { Tier } from '../../entities/index.js';
import { Message } from '../../entities/message.entity.js';
import { MessageType } from '../../entities/enums.js';
import { ChatRoom } from '../../entities/chat-room.entity.js';
import { gameAutoResolveQueue } from '../../queues/game-auto-resolve.queue.js';

// ─────────────────────────────────────
// 활동량 보너스 계산
// ─────────────────────────────────────

function calculateActivityBonus(params: {
  result: 'WIN' | 'LOSS' | 'DRAW';
  winStreak: number;
  gamesThisWeek: number;
  isFirstGameToday: boolean;
}): number {
  let bonus = 0;
  if (params.result === 'WIN') {
    // 연승 보너스
    if (params.winStreak >= 5) bonus += 8;
    else if (params.winStreak >= 3) bonus += 5;
    else if (params.winStreak >= 2) bonus += 3;
    // 오늘 첫 경기 보너스
    if (params.isFirstGameToday) bonus += 5;
  }
  return bonus;
}

function getAdjustedKFactor(base: number, gamesThisWeek: number): number {
  if (gamesThisWeek >= 5) return base + 4;
  if (gamesThisWeek >= 3) return base + 2;
  return base;
}

export class GamesService {
  private gameRepo;
  private matchRepo;
  private matchRequestRepo;
  private sportsProfileRepo;
  private resultConfirmationRepo;
  private scoreHistoryRepo;

  constructor(
    private dataSource: DataSource,
    private notificationService?: INotificationService,
  ) {
    this.gameRepo = dataSource.getRepository(Game);
    this.matchRepo = dataSource.getRepository(Match);
    this.matchRequestRepo = dataSource.getRepository(MatchRequest);
    this.sportsProfileRepo = dataSource.getRepository(SportsProfile);
    this.resultConfirmationRepo = dataSource.getRepository(ResultConfirmation);
    this.scoreHistoryRepo = dataSource.getRepository(ScoreHistory);
  }

  // ─────────────────────────────────────
  // 경기 결과 입력
  // ─────────────────────────────────────

  async submitResult(userId: string, gameId: string, dto: SubmitGameResultDto) {
    const game = await this.getGameWithAuth(userId, gameId);

    // PENDING 또는 PROOF_UPLOADED 상태만 결과 제출 허용
    if (!['PENDING', 'PROOF_UPLOADED'].includes(game.resultStatus)) {
      throw AppError.badRequest(
        ErrorCode.GAME_RESULT_ALREADY_SUBMITTED,
        '이미 인증이 완료되었거나 결과를 입력할 수 없는 상태입니다.',
      );
    }

    if (game.resultInputDeadline && new Date() > game.resultInputDeadline) {
      throw AppError.badRequest(ErrorCode.GAME_DEADLINE_EXCEEDED);
    }

    const match = game.match;
    const isRequester = (match.requesterProfile as any).userId === userId;

    // 인증번호 검증: 상대방의 코드를 입력해야 함
    const expectedCode = isRequester
      ? (match as any).opponentVerificationCode
      : (match as any).requesterVerificationCode;
    if (expectedCode && dto.verificationCode !== expectedCode) {
      throw AppError.badRequest(
        ErrorCode.VALIDATION_ERROR,
        '인증번호가 일치하지 않습니다. 상대방의 인증번호를 확인해주세요.',
      );
    }

    // 본인이 이미 제출했는지 확인 (claimedResult 기준)
    const alreadySubmittedByThisUser = isRequester
      ? (game as any).requesterClaimedResult !== null
      : (game as any).opponentClaimedResult !== null;

    if (alreadySubmittedByThisUser) {
      throw AppError.conflict(
        ErrorCode.GAME_RESULT_ALREADY_SUBMITTED,
        '이미 결과를 제출하셨습니다. 상대방의 결과 입력을 기다려 주세요.',
      );
    }

    // 제출자의 claimed result 결정 (명시적으로 전달받거나 점수로 추론)
    let claimedResult: 'WIN' | 'LOSS' | 'DRAW';
    if (dto.claimedResult) {
      claimedResult = dto.claimedResult;
    } else if (dto.myScore > dto.opponentScore) {
      claimedResult = 'WIN';
    } else if (dto.myScore < dto.opponentScore) {
      claimedResult = 'LOSS';
    } else {
      claimedResult = 'DRAW';
    }

    // 골프의 경우 핸디캡 적용 승자 결정 (점수 기반일 때만 — 명시적 claimedResult가 없을 때)
    if (game.sportType === 'GOLF' && !dto.claimedResult) {
      const requesterHandicap = Number((match.requesterProfile as any).gHandicap ?? 0);
      const opponentHandicap = Number((match.opponentProfile as any).gHandicap ?? 0);

      const golfResult = determineGolfWinner(
        isRequester ? dto.myScore : dto.opponentScore,
        isRequester ? dto.opponentScore : dto.myScore,
        requesterHandicap,
        opponentHandicap,
      );

      if (golfResult === 'REQUESTER') {
        claimedResult = isRequester ? 'WIN' : 'LOSS';
      } else if (golfResult === 'OPPONENT') {
        claimedResult = isRequester ? 'LOSS' : 'WIN';
      } else {
        claimedResult = 'DRAW';
      }
    }

    // claimed result 저장 + 점수 데이터 업데이트
    const updatePayload: Record<string, any> = {
      resultStatus: 'PROOF_UPLOADED' as any,
      requesterScore: isRequester ? dto.myScore : game.requesterScore,
      opponentScore: isRequester ? game.opponentScore : dto.myScore,
      playedAt: game.playedAt ?? (dto.playedAt ? new Date(dto.playedAt) : new Date()),
      scoreData: (dto.scoreData ?? game.scoreData ?? {}) as any,
    };

    if (dto.venueName) {
      updatePayload.venueName = dto.venueName;
    }

    if (isRequester) {
      updatePayload.requesterClaimedResult = claimedResult;
    } else {
      updatePayload.opponentClaimedResult = claimedResult;
    }

    await this.gameRepo.update(gameId, updatePayload);

    // 매너 점수 처리: 상대방 스포츠 프로필에 누적
    if (dto.mannerScore != null) {
      const opponentProfile = isRequester
        ? (match.opponentProfile as any)
        : (match.requesterProfile as any);

      await this.sportsProfileRepo
        .createQueryBuilder()
        .update(SportsProfile)
        .set({
          mannerTotal: () => `manner_total + ${dto.mannerScore}`,
          mannerCount: () => 'manner_count + 1',
        })
        .where('id = :id', { id: opponentProfile.id })
        .execute();
    }

    // 양측 claim이 모두 제출되었는지 확인
    const updatedGame = await this.gameRepo.findOne({ where: { id: gameId } });
    if (!updatedGame) {
      throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);
    }

    const requesterClaim = (updatedGame as any).requesterClaimedResult as string | null;
    const opponentClaim = (updatedGame as any).opponentClaimedResult as string | null;

    const opponentUserId = isRequester
      ? (match.opponentProfile as any).userId
      : (match.requesterProfile as any).userId;

    // 양측이 모두 제출한 경우 자동 결과 확정
    if (requesterClaim && opponentClaim) {
      return await this.resolveClaimedResults(
        gameId,
        updatedGame,
        match,
        requesterClaim as 'WIN' | 'LOSS' | 'DRAW',
        opponentClaim as 'WIN' | 'LOSS' | 'DRAW',
      );
    }

    // 채팅방에 결과 제출 시스템 메시지 전송
    if (match.chatRoomId) {
      const submitter = isRequester
        ? (match.requesterProfile as any).user
        : (match.opponentProfile as any).user;
      const submitterNickname = submitter?.nickname ?? '알 수 없음';

      // claimedResult가 WIN이면 제출자가 승자, LOSS이면 상대가 승자
      const winnerNickname = claimedResult === 'DRAW'
        ? null
        : claimedResult === 'WIN'
          ? submitterNickname
          : (isRequester
              ? (match.opponentProfile as any).user?.nickname
              : (match.requesterProfile as any).user?.nickname) ?? '상대';
      const winnerProfileImage = claimedResult === 'DRAW'
        ? null
        : claimedResult === 'WIN'
          ? submitter?.profileImageUrl ?? null
          : (isRequester
              ? (match.opponentProfile as any).user?.profileImageUrl
              : (match.requesterProfile as any).user?.profileImageUrl) ?? null;

      // 결과 텍스트: "OOO님이 승리로 결과를 입력했습니다"
      const resultLabel = claimedResult === 'WIN' ? '승리' : claimedResult === 'LOSS' ? '패배' : '무승부';
      const deadline = new Date(Date.now() + 3 * 60 * 1000);
      const kstTime = new Date(deadline.toLocaleString('en-US', { timeZone: 'Asia/Seoul' }));
      const deadlineHH = String(kstTime.getHours()).padStart(2, '0');
      const deadlineMM = String(kstTime.getMinutes()).padStart(2, '0');
      const content = `${submitterNickname}님이 ${resultLabel}(으)로 결과를 입력했습니다.\n3분 내(${deadlineHH}:${deadlineMM}) 상대방이 결과를 입력하지 않으면 자동으로 경기가 확정됩니다.`;

      const messageRepo = this.dataSource.getRepository(Message);
      const chatRoomRepo = this.dataSource.getRepository(ChatRoom);
      const sysMsg = messageRepo.create({
        chatRoomId: match.chatRoomId,
        senderId: userId,
        messageType: MessageType.SYSTEM,
        content,
        extraData: {
          type: 'GAME_RESULT',
          claimedResult,
          submitterNickname,
          winnerNickname,
          winnerProfileImage,
        },
      });
      const savedMsg = await messageRepo.save(sysMsg);
      await chatRoomRepo.update(match.chatRoomId, { lastMessageAt: new Date() });

      // 채팅방에 실시간 시스템 메시지 브로드캐스트 (직접 emit)
      const msgData = {
        id: savedMsg.id,
        roomId: match.chatRoomId,
        sender: null,
        content: savedMsg.content,
        messageType: 'SYSTEM',
        extraData: savedMsg.extraData,
        readAt: null,
        createdAt: savedMsg.createdAt,
      };
      try {
        const io = (global as any).__io;
        if (io) {
          io.to(`room:${match.chatRoomId}`).emit('NEW_MESSAGE', msgData);
        } else {
          await redis.publish('chat_room_message', JSON.stringify({ roomId: match.chatRoomId, message: msgData }));
        }
      } catch (pubErr) {
        console.warn('[SubmitResult] chat message broadcast failed:', pubErr);
      }
    }

    // 한 쪽만 제출한 경우: 상대방에게 알림
    if (this.notificationService) {
      await this.notificationService.send({
        userId: opponentUserId,
        type: 'GAME_RESULT_SUBMITTED',
        title: '경기 결과 입력 요청',
        body: '상대방이 경기 결과를 입력했습니다. 3분 내에 결과를 입력해 주세요.',
        data: { gameId, deepLink: `/games/${gameId}/result` },
      });
    }

    // 3분 후 자동 확정 delayed job 등록 (상대방 미입력 시 제출된 결과 채택)
    await gameAutoResolveQueue.add(
      'auto-resolve-single',
      { gameId },
      {
        delay: 3 * 60 * 1000, // 3분
        jobId: `auto-resolve-${gameId}`,
        removeOnComplete: true,
        removeOnFail: { count: 3 },
      },
    );

    return { status: 'PROOF_UPLOADED', message: '결과가 저장되었습니다. 상대방의 결과 입력을 기다립니다.' };
  }

  // ─────────────────────────────────────
  // 양측 claimed result 자동 확정
  // ─────────────────────────────────────

  private async resolveClaimedResults(
    gameId: string,
    game: any,
    match: any,
    requesterClaim: 'WIN' | 'LOSS' | 'DRAW',
    opponentClaim: 'WIN' | 'LOSS' | 'DRAW',
  ) {
    const requesterProfileId = (match.requesterProfile as any).id;
    const opponentProfileId = (match.opponentProfile as any).id;

    // 결과 합의 로직
    // WIN + LOSS (requester가 이겼다고, opponent가 졌다고) → requester 승
    // LOSS + WIN (requester가 졌다고, opponent가 이겼다고) → opponent 승
    // 그 외 모든 불일치 (WIN+WIN, LOSS+LOSS, WIN+DRAW, DRAW+WIN 등) → DRAW
    let resolvedWinnerProfileId: string | null;
    let resolvedResult: 'WIN' | 'LOSS' | 'DRAW';

    if (requesterClaim === 'WIN' && opponentClaim === 'LOSS') {
      // 완전 합의: requester 승
      resolvedWinnerProfileId = requesterProfileId;
      resolvedResult = 'WIN'; // requester 기준
    } else if (requesterClaim === 'LOSS' && opponentClaim === 'WIN') {
      // 완전 합의: opponent 승
      resolvedWinnerProfileId = opponentProfileId;
      resolvedResult = 'LOSS'; // requester 기준
    } else if (requesterClaim === 'DRAW' && opponentClaim === 'DRAW') {
      // 양측 무승부 합의
      resolvedWinnerProfileId = null;
      resolvedResult = 'DRAW';
    } else {
      // 불일치 (WIN+WIN, LOSS+LOSS, 한쪽 DRAW 등) → 무승부 처리
      resolvedWinnerProfileId = null;
      resolvedResult = 'DRAW';
    }

    const isAgreement =
      (requesterClaim === 'WIN' && opponentClaim === 'LOSS') ||
      (requesterClaim === 'LOSS' && opponentClaim === 'WIN') ||
      (requesterClaim === 'DRAW' && opponentClaim === 'DRAW');

    await this.gameRepo.update(gameId, { winnerProfileId: resolvedWinnerProfileId });

    let isCasual = false;
    let message: string;

    if (isAgreement) {
      // 결과 합의 → ELO 점수 반영
      try {
        isCasual = await this.applyEloChanges(gameId, { ...game, winnerProfileId: resolvedWinnerProfileId }, match);
      } catch (eloError) {
        console.error('[GamesService] applyEloChanges 실패 — Match COMPLETED 폴백 처리:', eloError);
        try {
          await this.gameRepo.update(gameId, {
            resultStatus: 'VERIFIED' as any,
            verifiedAt: new Date(),
          });
          const matchRepo = this.dataSource.getRepository(Match);
          await matchRepo.update(game.matchId, {
            status: 'COMPLETED' as any,
            completedAt: new Date(),
          });
        } catch (fallbackErr) {
          console.error('[GamesService] fallback COMPLETED 업데이트 실패:', fallbackErr);
        }
      }
      message = isCasual
        ? '친선 경기 결과가 확정되었습니다.'
        : '경기 결과가 확정되었습니다. 점수가 반영되었습니다.';
    } else {
      // 결과 불일치 → 점수 변동 없이 DISPUTED 상태로 처리 (어드민 검토 대기)
      await this.gameRepo.update(gameId, {
        resultStatus: 'DISPUTED' as any,
        verifiedAt: new Date(),
      });
      const matchRepo = this.dataSource.getRepository(Match);
      await matchRepo.update(game.matchId, {
        status: 'COMPLETED' as any,
        completedAt: new Date(),
      });

      // DISPUTED여도 해당 핀에 ranking_entry 생성 (점수 변동 없이 기록만)
      if (match.pinId) {
        const rankingEntryRepoDisputed = this.dataSource.getRepository(RankingEntry);
        const sportType = (match.requesterProfile as any).sportType;
        for (const profile of [match.requesterProfile, match.opponentProfile]) {
          const profileId = (profile as any).id;
          const profileScore = (profile as any).currentScore ?? 1000;
          const existing = await rankingEntryRepoDisputed.findOne({
            where: { pinId: match.pinId, sportsProfileId: profileId, sportType: sportType as any },
          });
          if (existing) {
            await rankingEntryRepoDisputed.update(existing.id, {
              gamesPlayed: (existing.gamesPlayed ?? 0) + 1,
            });
          } else {
            await rankingEntryRepoDisputed.save(rankingEntryRepoDisputed.create({
              pinId: match.pinId,
              sportsProfileId: profileId,
              sportType: sportType as any,
              score: profileScore,
              rank: 0,
              tier: 'IRON' as any,
              gamesPlayed: 1,
            }));
          }
        }
      }

      message = '결과가 일치하지 않아 점수 변동 없이 처리되었습니다. 이의 제기를 통해 운영자에게 검토를 요청할 수 있습니다.';
    }

    // 채팅방에 확정 시스템 메시지 전송
    if (match.chatRoomId) {
      const messageRepo = this.dataSource.getRepository(Message);
      const chatRoomRepo = this.dataSource.getRepository(ChatRoom);
      const sysMsg = messageRepo.create({
        chatRoomId: match.chatRoomId,
        senderId: (match.requesterProfile as any).userId,
        messageType: MessageType.SYSTEM,
        content: message,
        extraData: { type: 'GAME_RESOLVED', resolvedResult, isAgreement },
      });
      const savedMsg = await messageRepo.save(sysMsg);
      await chatRoomRepo.update(match.chatRoomId, { lastMessageAt: new Date() });

      const resolvedMsgData = {
        id: savedMsg.id,
        roomId: match.chatRoomId,
        sender: null,
        content: savedMsg.content,
        messageType: 'SYSTEM',
        extraData: savedMsg.extraData,
        readAt: null,
        createdAt: savedMsg.createdAt,
      };
      try {
        const io = (global as any).__io;
        if (io) {
          io.to(`room:${match.chatRoomId}`).emit('NEW_MESSAGE', resolvedMsgData);
        } else {
          await redis.publish('chat_room_message', JSON.stringify({ roomId: match.chatRoomId, message: resolvedMsgData }));
        }
      } catch (pubErr) {
        console.warn('[GamesService] chat message broadcast failed:', pubErr);
      }
    }

    // 경기 완료 → COMPLETED 상태 실시간 전달 (WS 먼저, push 나중)
    try {
      await redis.publish('match_lifecycle', JSON.stringify({
        event: 'MATCH_STATUS_CHANGED',
        matchId: match.id,
        data: { matchId: match.id, status: 'COMPLETED', gameId },
      }));
    } catch (pubErr) {
      console.warn('[GamesService] match_lifecycle publish failed:', pubErr);
    }

    // 양쪽 유저에게 MATCH_COMPLETED 알림
    if (this.notificationService) {
      await this.notificationService.sendBulk([
        {
          userId: (match.requesterProfile as any).userId,
          type: 'MATCH_COMPLETED',
          title: '경기 완료',
          body: message,
          data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
        },
        {
          userId: (match.opponentProfile as any).userId,
          type: 'MATCH_COMPLETED',
          title: '경기 완료',
          body: message,
          data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
        },
      ]);
    }

    return {
      status: 'VERIFIED',
      resolvedResult,
      isAgreement,
      isCasual,
      message,
    };
  }

  // ─────────────────────────────────────
  // 결과 인증 (동의/거절)
  // ─────────────────────────────────────

  async confirmResult(userId: string, gameId: string, dto: ConfirmGameResultDto) {
    const game = await this.getGameWithAuth(userId, gameId);

    if (!['PROOF_UPLOADED', 'PENDING'].includes(game.resultStatus)) {
      throw AppError.badRequest(
        ErrorCode.GAME_ALREADY_CONFIRMED,
        '인증할 수 없는 상태의 경기입니다.',
      );
    }

    // 이미 인증했는지 확인
    const existingConfirmation = await this.resultConfirmationRepo.findOne({
      where: { gameId, userId },
    });

    if (existingConfirmation) {
      throw AppError.conflict(
        ErrorCode.GAME_ALREADY_CONFIRMED,
        '이미 결과를 인증했습니다.',
      );
    }

    await this.resultConfirmationRepo.save(
      this.resultConfirmationRepo.create({
        gameId,
        userId,
        isConfirmed: dto.isConfirmed,
        comment: dto.comment,
      }),
    );

    // 양측 모두 인증했는지 확인
    const confirmations = await this.resultConfirmationRepo.find({ where: { gameId } });

    const match = game.match;
    const bothConfirmed = confirmations.length === 2 && confirmations.every((c) => c.isConfirmed);
    const anyRejected = confirmations.some((c) => !c.isConfirmed);

    if (anyRejected) {
      // 한 쪽이라도 거절 → DISPUTED
      await this.gameRepo.update(gameId, { resultStatus: 'DISPUTED' as any });

      return { status: 'DISPUTED', message: '결과가 거절되어 이의 신청 상태로 변경되었습니다.' };
    }

    if (bothConfirmed) {
      // 양측 동의 → 점수 반영
      const isCasualGame = await this.applyEloChanges(gameId, game, match);

      return {
        status: 'VERIFIED',
        isCasual: isCasualGame,
        message: isCasualGame
          ? '친선 경기 결과가 인증되었습니다. 친선 점수에만 반영됩니다.'
          : '경기 결과가 인증되었습니다. 점수가 반영되었습니다.',
      };
    }

    return {
      status: 'PROOF_UPLOADED',
      message: '인증 완료. 상대방 인증을 기다리고 있습니다.',
    };
  }

  // ─────────────────────────────────────
  // ELO 점수 반영
  // ─────────────────────────────────────

  private async applyEloChanges(gameId: string, game: any, match: any): Promise<boolean> {
    // 캐주얼 모드 여부 확인 (matchRequest.isCasual)
    let isCasual = false;
    if (match.matchRequestId) {
      const matchRequest = await this.matchRequestRepo.findOne({
        where: { id: match.matchRequestId },
        select: { isCasual: true } as any,
      });
      isCasual = (matchRequest as any)?.isCasual === true;
    }

    const requesterProfile = match.requesterProfile;
    const opponentProfile = match.opponentProfile;

    // 승자 판단
    let resultForRequester: 'WIN' | 'LOSS' | 'DRAW';
    if (!game.winnerProfileId) {
      resultForRequester = 'DRAW';
    } else if (game.winnerProfileId === requesterProfile.id) {
      resultForRequester = 'WIN';
    } else {
      resultForRequester = 'LOSS';
    }

    // 캐주얼 게임: K=20 고정, casualScore/casualWin/casualLoss만 업데이트
    const CASUAL_K_FACTOR = 20;

    const kFactorRequester = isCasual ? CASUAL_K_FACTOR : getKFactor(requesterProfile.gamesPlayed, requesterProfile.tier as Tier);
    const kFactorOpponent = isCasual ? CASUAL_K_FACTOR : getKFactor(opponentProfile.gamesPlayed, opponentProfile.tier as Tier);

    // 캐주얼은 casualScore 기준으로 ELO 계산, 일반은 해당 핀의 ranking_entries.score 기준
    // 핀이 있는 경우 핀별 독립 점수 조회, 없거나 캐주얼이면 글로벌/casual 점수 사용
    let requesterBaseScore: number;
    let opponentBaseScore: number;

    if (isCasual) {
      requesterBaseScore = requesterProfile.casualScore ?? 1000;
      opponentBaseScore = opponentProfile.casualScore ?? 1000;
    } else if (match.pinId) {
      // 핀별 독립 점수 조회 (없으면 1000 기본값)
      const rankingEntryRepoForScore = this.dataSource.getRepository(RankingEntry);
      const sportTypeForScore = requesterProfile.sportType;

      const [reqPinEntry, oppPinEntry] = await Promise.all([
        rankingEntryRepoForScore.findOne({
          where: {
            pinId: match.pinId,
            sportsProfileId: requesterProfile.id,
            sportType: sportTypeForScore as any,
          },
        }),
        rankingEntryRepoForScore.findOne({
          where: {
            pinId: match.pinId,
            sportsProfileId: opponentProfile.id,
            sportType: sportTypeForScore as any,
          },
        }),
      ]);

      // 핀에 기록이 없으면 글로벌 점수로 시작 (실력 반영, 스머핑 방지)
      requesterBaseScore = reqPinEntry?.score ?? requesterProfile.currentScore;
      opponentBaseScore = oppPinEntry?.score ?? opponentProfile.currentScore;
    } else {
      // 핀 없는 매칭: 글로벌 점수 사용
      requesterBaseScore = requesterProfile.currentScore;
      opponentBaseScore = opponentProfile.currentScore;
    }

    // 활동량 데이터 조회 (일반 게임에서만 사용)
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const todayStart = getKSTMidnight(); // KST 자정 기준

    const [requesterWeekHistory, opponentWeekHistory] = await Promise.all([
      this.scoreHistoryRepo
        .createQueryBuilder('sh')
        .where('sh.sportsProfileId = :id AND sh.createdAt >= :since AND sh.changeType IN (:...types)', {
          id: requesterProfile.id,
          since: sevenDaysAgo,
          types: ['GAME_WIN', 'GAME_LOSS', 'GAME_DRAW'],
        })
        .orderBy('sh.createdAt', 'DESC')
        .getMany(),
      this.scoreHistoryRepo
        .createQueryBuilder('sh')
        .where('sh.sportsProfileId = :id AND sh.createdAt >= :since AND sh.changeType IN (:...types)', {
          id: opponentProfile.id,
          since: sevenDaysAgo,
          types: ['GAME_WIN', 'GAME_LOSS', 'GAME_DRAW'],
        })
        .orderBy('sh.createdAt', 'DESC')
        .getMany(),
    ]);

    // 연승 (winStreak) 은 엔티티에서 직접 참조
    const requesterWinStreak = isCasual ? 0 : (requesterProfile.winStreak ?? 0);
    const opponentWinStreak = isCasual ? 0 : (opponentProfile.winStreak ?? 0);

    // 이번 주 게임 수
    const requesterGamesThisWeek = requesterWeekHistory.length;
    const opponentGamesThisWeek = opponentWeekHistory.length;

    // 오늘 첫 경기 여부
    const requesterIsFirstToday = !requesterWeekHistory.some(
      (h) => h.createdAt >= todayStart,
    );
    const opponentIsFirstToday = !opponentWeekHistory.some(
      (h) => h.createdAt >= todayStart,
    );

    const resultForOpponent: 'WIN' | 'LOSS' | 'DRAW' =
      resultForRequester === 'WIN' ? 'LOSS' : resultForRequester === 'LOSS' ? 'WIN' : 'DRAW';

    // 활동량 보너스 계산 (일반 게임에서만)
    const requesterBonus = isCasual ? 0 : calculateActivityBonus({
      result: resultForRequester,
      winStreak: requesterWinStreak,
      gamesThisWeek: requesterGamesThisWeek,
      isFirstGameToday: requesterIsFirstToday,
    });
    const opponentBonus = isCasual ? 0 : calculateActivityBonus({
      result: resultForOpponent,
      winStreak: opponentWinStreak,
      gamesThisWeek: opponentGamesThisWeek,
      isFirstGameToday: opponentIsFirstToday,
    });

    // K 계수 활동량 보정 (일반 게임에서만)
    const adjustedKRequester = isCasual
      ? kFactorRequester
      : getAdjustedKFactor(kFactorRequester, requesterGamesThisWeek);
    const adjustedKOpponent = isCasual
      ? kFactorOpponent
      : getAdjustedKFactor(kFactorOpponent, opponentGamesThisWeek);

    const { newScoreA: baseNewScoreA, changeA, newScoreB: baseNewScoreB, changeB } = calculateBothElo(
      requesterBaseScore,
      opponentBaseScore,
      adjustedKRequester,
      adjustedKOpponent,
      resultForRequester,
    );

    // 활동량 보너스 적용 (최소 100점 보장)
    const newScoreA = Math.max(100, baseNewScoreA + requesterBonus);
    const newScoreB = Math.max(100, baseNewScoreB + opponentBonus);

    // ─────────────────────────────────────
    // Glicko-2 업데이트 (일반 게임에서만)
    // ─────────────────────────────────────
    let glickoRequester: Glicko2Rating | null = null;
    let glickoOpponent: Glicko2Rating | null = null;

    if (!isCasual) {
      const requesterGlickoRating: Glicko2Rating = {
        rating: requesterProfile.glickoRating ?? 1000,
        rd: requesterProfile.glickoRd ?? 350,
        volatility: requesterProfile.glickoVolatility ?? 0.06,
      };
      const opponentGlickoRating: Glicko2Rating = {
        rating: opponentProfile.glickoRating ?? 1000,
        rd: opponentProfile.glickoRd ?? 350,
        volatility: opponentProfile.glickoVolatility ?? 0.06,
      };

      const requesterScore = resultForRequester === 'WIN' ? 1.0 : resultForRequester === 'LOSS' ? 0.0 : 0.5;
      const opponentScore = resultForOpponent === 'WIN' ? 1.0 : resultForOpponent === 'LOSS' ? 0.0 : 0.5;

      const requesterResults: Glicko2Result[] = [{
        opponentRating: opponentGlickoRating.rating,
        opponentRd: opponentGlickoRating.rd,
        score: requesterScore,
      }];
      const opponentResults: Glicko2Result[] = [{
        opponentRating: requesterGlickoRating.rating,
        opponentRd: requesterGlickoRating.rd,
        score: opponentScore,
      }];

      glickoRequester = updateGlicko2(requesterGlickoRating, requesterResults);
      glickoOpponent = updateGlicko2(opponentGlickoRating, opponentResults);
    }

    // 핀별 독립 점수 체계: ELO 기반 점수 사용 (Glicko-2는 매치메이킹 MMR 전용)
    // 글로벌 Glicko-2 레이팅은 핀별 점수와 다를 수 있어 display에 사용하면 승패 점수가 뒤바뀜
    const finalDisplayScoreA = newScoreA;
    const finalDisplayScoreB = newScoreB;

    // 티어는 트랜잭션 안에서 ranking_entries upsert 후 점수 기반으로 계산
    let newTierRequester = requesterProfile.tier as Tier;
    let newTierOpponent = opponentProfile.tier as Tier;

    const txResult = await this.dataSource.transaction(async (manager) => {
      // 비관적 잠금: 다중 인스턴스에서 동시 처리 방지 (SELECT FOR UPDATE)
      const lockedGame = await manager
        .createQueryBuilder(Game, 'game')
        .setLock('pessimistic_write')
        .where('game.id = :id', { id: gameId })
        .getOne();

      if (!lockedGame || (lockedGame as any).resultStatus === 'VERIFIED') {
        return { skipped: true }; // 이미 처리됨 — 다른 인스턴스가 먼저 처리
      }

      if (isCasual) {
        // 캐주얼: casualScore/casualWin/casualLoss만 업데이트, 메인 점수/티어/wins/losses 변경 없음
        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({
            casualScore: newScoreA,
            ...(resultForRequester === 'WIN' ? { casualWin: () => 'casual_win + 1' } : {}),
            ...(resultForRequester === 'LOSS' ? { casualLoss: () => 'casual_loss + 1' } : {}),
          })
          .where('id = :id', { id: requesterProfile.id })
          .execute();

        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({
            casualScore: newScoreB,
            ...(resultForOpponent === 'WIN' ? { casualWin: () => 'casual_win + 1' } : {}),
            ...(resultForOpponent === 'LOSS' ? { casualLoss: () => 'casual_loss + 1' } : {}),
          })
          .where('id = :id', { id: opponentProfile.id })
          .execute();
      } else {
        // ─────────────────────────────────────
        // 일반 게임: Glicko-2 + 활동 보너스 적용
        // ─────────────────────────────────────

        // glickoRating = 순수 Glicko-2 (MMR), displayScore = glickoRating + bonus (사용자 노출), currentScore = displayScore
        // finalDisplayScoreA/B는 트랜잭션 외부에서 이미 계산됨

        // gamesPlayed after this game (used for isPlacement)
        const reqGamesAfter = (requesterProfile.gamesPlayed ?? 0) + 1;
        const oppGamesAfter = (opponentProfile.gamesPlayed ?? 0) + 1;

        // recentOpponentIds: 최신 상대 profileId를 앞에 추가하고 최대 5개 유지
        const reqRecentOpponents = [
          opponentProfile.id,
          ...(requesterProfile.recentOpponentIds ?? []),
        ].slice(0, 5);
        const oppRecentOpponents = [
          requesterProfile.id,
          ...(opponentProfile.recentOpponentIds ?? []),
        ].slice(0, 5);

        // lossStreak: 패배 시 +1, 승리/무승부 시 리셋
        const reqLossStreak = resultForRequester === 'LOSS'
          ? (requesterProfile.lossStreak ?? 0) + 1
          : 0;
        const oppLossStreak = resultForOpponent === 'LOSS'
          ? (opponentProfile.lossStreak ?? 0) + 1
          : 0;

        // ─────────────────────────────────────
        // 핀별 ranking_entries 업데이트 (핀이 있는 일반 게임)
        // ─────────────────────────────────────
        let reqNewCurrentScore = finalDisplayScoreA;
        let oppNewCurrentScore = finalDisplayScoreB;

        if (match.pinId) {
          const rankingEntryRepo = manager.getRepository(RankingEntry);
          const sportType = requesterProfile.sportType;

          // 요청자 ranking_entry upsert
          const existingReqEntry = await rankingEntryRepo.findOne({
            where: {
              pinId: match.pinId,
              sportsProfileId: requesterProfile.id,
              sportType: sportType as any,
            },
          });

          if (existingReqEntry) {
            await rankingEntryRepo.update(existingReqEntry.id, {
              score: finalDisplayScoreA,
              gamesPlayed: (existingReqEntry.gamesPlayed ?? 0) + 1,
            });
          } else {
            const newReqEntry = rankingEntryRepo.create({
              pinId: match.pinId,
              sportsProfileId: requesterProfile.id,
              sportType: sportType as any,
              score: finalDisplayScoreA,
              rank: 0,
              tier: newTierRequester,
              gamesPlayed: 1,
            });
            await rankingEntryRepo.save(newReqEntry);
          }

          // 상대방 ranking_entry upsert
          const existingOppEntry = await rankingEntryRepo.findOne({
            where: {
              pinId: match.pinId,
              sportsProfileId: opponentProfile.id,
              sportType: sportType as any,
            },
          });

          if (existingOppEntry) {
            await rankingEntryRepo.update(existingOppEntry.id, {
              score: finalDisplayScoreB,
              gamesPlayed: (existingOppEntry.gamesPlayed ?? 0) + 1,
            });
          } else {
            const newOppEntry = rankingEntryRepo.create({
              pinId: match.pinId,
              sportsProfileId: opponentProfile.id,
              sportType: sportType as any,
              score: finalDisplayScoreB,
              rank: 0,
              tier: newTierOpponent,
              gamesPlayed: 1,
            });
            await rankingEntryRepo.save(newOppEntry);
          }

          // sports_profiles.currentScore = 해당 유저의 모든 ranking_entries 중 최고점
          const [reqMaxResult, oppMaxResult] = await Promise.all([
            rankingEntryRepo
              .createQueryBuilder('re')
              .select('MAX(re.score)', 'maxScore')
              .where('re.sportsProfileId = :id AND re.sportType = :sportType', {
                id: requesterProfile.id,
                sportType,
              })
              .getRawOne<{ maxScore: number }>(),
            rankingEntryRepo
              .createQueryBuilder('re')
              .select('MAX(re.score)', 'maxScore')
              .where('re.sportsProfileId = :id AND re.sportType = :sportType', {
                id: opponentProfile.id,
                sportType,
              })
              .getRawOne<{ maxScore: number }>(),
          ]);

          reqNewCurrentScore = reqMaxResult?.maxScore ?? finalDisplayScoreA;
          oppNewCurrentScore = oppMaxResult?.maxScore ?? finalDisplayScoreB;

          // 해당 핀+스포츠의 등수 즉시 재계산 (점수 높은 순)
          const allEntries = await rankingEntryRepo.find({
            where: { pinId: match.pinId, sportType: sportType as any },
            order: { score: 'DESC' },
          });
          for (let i = 0; i < allEntries.length; i++) {
            const newRank = i + 1;
            const newTier = calculateTierByRank(newRank, allEntries.length);
            await rankingEntryRepo.update(allEntries[i].id, { rank: newRank, tier: newTier });
            // 현재 유저들의 티어도 갱신
            if (allEntries[i].sportsProfileId === requesterProfile.id) {
              newTierRequester = newTier;
            }
            if (allEntries[i].sportsProfileId === opponentProfile.id) {
              newTierOpponent = newTier;
            }
          }
        }

        // 일반: 요청자 점수 + Glicko-2 + 부가 통계 업데이트
        // glickoRating = 순수 Glicko-2 (MMR), displayScore = glickoRating + bonus (사용자 노출)
        // currentScore = 핀이 있으면 모든 핀 중 최고점, 없으면 displayScore
        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({
            displayScore: finalDisplayScoreA,
            currentScore: reqNewCurrentScore,
            tier: newTierRequester,
            gamesPlayed: () => 'games_played + 1',
            isPlacement: reqGamesAfter < 5,
            lossStreak: reqLossStreak,
            recentOpponentIds: reqRecentOpponents,
            ...(glickoRequester ? {
              glickoRating: glickoRequester.rating,
              glickoRd: glickoRequester.rd,
              glickoVolatility: glickoRequester.volatility,
              glickoLastUpdatedAt: new Date(),
            } : {}),
            ...(resultForRequester === 'WIN' ? { wins: () => 'wins + 1', winStreak: () => 'win_streak + 1' } : {}),
            ...(resultForRequester === 'LOSS' ? { losses: () => 'losses + 1', winStreak: 0 } : {}),
            ...(resultForRequester === 'DRAW' ? { draws: () => 'draws + 1', winStreak: 0 } : {}),
          })
          .where('id = :id', { id: requesterProfile.id })
          .execute();

        // 일반: 상대방 점수 + Glicko-2 + 부가 통계 업데이트
        await manager
          .createQueryBuilder()
          .update(SportsProfile)
          .set({
            displayScore: finalDisplayScoreB,
            currentScore: oppNewCurrentScore,
            tier: newTierOpponent,
            gamesPlayed: () => 'games_played + 1',
            isPlacement: oppGamesAfter < 5,
            lossStreak: oppLossStreak,
            recentOpponentIds: oppRecentOpponents,
            ...(glickoOpponent ? {
              glickoRating: glickoOpponent.rating,
              glickoRd: glickoOpponent.rd,
              glickoVolatility: glickoOpponent.volatility,
              glickoLastUpdatedAt: new Date(),
            } : {}),
            ...(resultForOpponent === 'WIN' ? { wins: () => 'wins + 1', winStreak: () => 'win_streak + 1' } : {}),
            ...(resultForOpponent === 'LOSS' ? { losses: () => 'losses + 1', winStreak: 0 } : {}),
            ...(resultForOpponent === 'DRAW' ? { draws: () => 'draws + 1', winStreak: 0 } : {}),
          })
          .where('id = :id', { id: opponentProfile.id })
          .execute();
      }

      // 점수 히스토리 기록 (일반 게임만 — 친선 게임은 메인 점수에 영향 없으므로 기록 제외)
      if (!isCasual) {
        const reqGamesAfterForHistory = (requesterProfile.gamesPlayed ?? 0) + 1;
        const isReqPlacementGame = reqGamesAfterForHistory <= 5;
        const isOppPlacementGame = (opponentProfile.gamesPlayed ?? 0) + 1 <= 5;

        const finalScoreAForHistory = finalDisplayScoreA;
        const finalScoreBForHistory = finalDisplayScoreB;

        await manager.save(ScoreHistory, [
          manager.create(ScoreHistory, {
            sportsProfileId: requesterProfile.id,
            gameId,
            changeType:
              resultForRequester === 'WIN'
                ? ('GAME_WIN' as any)
                : resultForRequester === 'LOSS'
                ? ('GAME_LOSS' as any)
                : ('GAME_DRAW' as any),
            scoreBefore: requesterBaseScore,
            scoreChange: finalScoreAForHistory - requesterBaseScore,
            scoreAfter: finalScoreAForHistory,
            opponentScore: opponentBaseScore,
            kFactor: adjustedKRequester,
            rdBefore: requesterProfile.glickoRd ?? null,
            rdAfter: glickoRequester?.rd ?? null,
            volatilityBefore: requesterProfile.glickoVolatility ?? null,
            volatilityAfter: glickoRequester?.volatility ?? null,
            isPlacementGame: isReqPlacementGame,
          }),
          manager.create(ScoreHistory, {
            sportsProfileId: opponentProfile.id,
            gameId,
            changeType:
              resultForOpponent === 'WIN'
                ? ('GAME_WIN' as any)
                : resultForOpponent === 'LOSS'
                ? ('GAME_LOSS' as any)
                : ('GAME_DRAW' as any),
            scoreBefore: opponentBaseScore,
            scoreChange: finalScoreBForHistory - opponentBaseScore,
            scoreAfter: finalScoreBForHistory,
            opponentScore: requesterBaseScore,
            kFactor: adjustedKOpponent,
            rdBefore: opponentProfile.glickoRd ?? null,
            rdAfter: glickoOpponent?.rd ?? null,
            volatilityBefore: opponentProfile.glickoVolatility ?? null,
            volatilityAfter: glickoOpponent?.volatility ?? null,
            isPlacementGame: isOppPlacementGame,
          }),
        ]);
      }

      // 게임 상태 업데이트
      await manager.update(Game, gameId, {
        resultStatus: 'VERIFIED' as any,
        verifiedAt: new Date(),
      });

      // 매칭 상태 완료로 변경
      await manager.update(Match, match.id, {
        status: 'COMPLETED' as any,
        completedAt: new Date(),
      });

      // matchRequest 상태도 EXPIRED로 변경 (중복 매칭 요청 방지)
      if (match.matchRequestId) {
        await manager.update(MatchRequest, match.matchRequestId, {
          status: 'EXPIRED' as any,
        });
      }

      return { skipped: false };
    });

    // 이미 다른 인스턴스에서 처리된 경우 알림 스킵
    if (txResult.skipped) {
      return false;
    }

    // 알림 발송
    if (this.notificationService) {
      const notifs: NotificationPayload[] = [];

      // 최종 점수 결정: 일반 게임은 displayScore(glickoRating + bonus), 캐주얼은 ELO 기반
      const finalNotifScoreA = isCasual ? newScoreA : finalDisplayScoreA;
      const finalNotifScoreB = isCasual ? newScoreB : finalDisplayScoreB;
      const notifChangeA = finalNotifScoreA - requesterBaseScore;
      const notifChangeB = finalNotifScoreB - opponentBaseScore;

      const scoreTitleA = notifChangeA >= 0
        ? `경기 결과: +${notifChangeA}점 획득!`
        : `경기 결과: ${notifChangeA}점`;
      const scoreTitleB = notifChangeB >= 0
        ? `경기 결과: +${notifChangeB}점 획득!`
        : `경기 결과: ${notifChangeB}점`;

      notifs.push({
        userId: requesterProfile.userId,
        type: 'SCORE_UPDATED',
        title: isCasual ? '[친선] 경기 완료' : scoreTitleA,
        body: isCasual ? '친선 경기가 완료되었습니다.' : `현재 점수: ${finalNotifScoreA}점`,
        data: { gameId, deepLink: '/profile/score', isCasual: String(isCasual) },
      });

      notifs.push({
        userId: opponentProfile.userId,
        type: 'SCORE_UPDATED',
        title: isCasual ? '[친선] 경기 완료' : scoreTitleB,
        body: isCasual ? '친선 경기가 완료되었습니다.' : `현재 점수: ${finalNotifScoreB}점`,
        data: { gameId, deepLink: '/profile/score', isCasual: String(isCasual) },
      });

      // 티어 변경 알림 (캐주얼은 티어 영향 없음)
      if (!isCasual) {
        const tierKo = (t: string) => {
          const m: Record<string, string> = { IRON: '아이언', BRONZE: '브론즈', SILVER: '실버', GOLD: '골드', PLATINUM: '플래티넘', MASTER: '마스터', GRANDMASTER: '그랜드마스터' };
          return m[t.toUpperCase()] ?? t;
        };
        const isUp = (from: string, to: string) => {
          const order = ['IRON','BRONZE','SILVER','GOLD','PLATINUM','MASTER','GRANDMASTER'];
          return order.indexOf(to.toUpperCase()) > order.indexOf(from.toUpperCase());
        };

        if (newTierRequester !== requesterProfile.tier) {
          const up = isUp(requesterProfile.tier, newTierRequester);
          notifs.push({
            userId: requesterProfile.userId,
            type: 'TIER_CHANGED',
            title: up ? '축하합니다! 티어가 승급되었습니다!' : '티어가 변경되었습니다',
            body: `${tierKo(requesterProfile.tier)} → ${tierKo(newTierRequester)}`,
            data: { deepLink: '/profile/score' },
          });
        }

        if (newTierOpponent !== opponentProfile.tier) {
          const up = isUp(opponentProfile.tier, newTierOpponent);
          notifs.push({
            userId: opponentProfile.userId,
            type: 'TIER_CHANGED',
            title: up ? '축하합니다! 티어가 승급되었습니다!' : '티어가 변경되었습니다',
            body: `${tierKo(opponentProfile.tier)} → ${tierKo(newTierOpponent)}`,
            data: { deepLink: '/profile/score' },
          });
        }
      }

      await this.notificationService.sendBulk(notifs);
    }

    return isCasual;
  }

  // ─────────────────────────────────────
  // 이의 신청
  // ─────────────────────────────────────

  async disputeResult(userId: string, gameId: string, dto: DisputeGameResultDto) {
    const game = await this.getGameWithAuth(userId, gameId);

    if (game.resultStatus === 'DISPUTED') {
      throw AppError.badRequest(ErrorCode.GAME_ALREADY_DISPUTED);
    }

    if (!['PROOF_UPLOADED', 'VERIFIED'].includes(game.resultStatus)) {
      throw AppError.badRequest(ErrorCode.MATCH_INVALID_STATUS, '이의 신청할 수 없는 상태입니다.');
    }

    // VERIFIED 상태에서는 48시간 이내만 가능
    if (game.resultStatus === 'VERIFIED' && game.verifiedAt) {
      const hoursSinceVerification = (Date.now() - game.verifiedAt.getTime()) / (1000 * 60 * 60);
      if (hoursSinceVerification > 48) {
        throw AppError.badRequest(ErrorCode.GAME_ALREADY_CONFIRMED, '인증 후 48시간이 지나 이의 신청을 할 수 없습니다.');
      }
    }

    await this.dataSource.transaction(async (manager) => {
      await manager.update(Game, gameId, { resultStatus: 'DISPUTED' as any });
      await manager.update(Match, game.matchId, { status: 'DISPUTED' as any });
    });

    return { status: 'DISPUTED', message: '이의 신청이 접수되었습니다. 관리자가 검토합니다.' };
  }

  // ─────────────────────────────────────
  // 경기 상세 조회
  // ─────────────────────────────────────

  async getGame(userId: string, gameId: string) {
    return this.getGameWithAuth(userId, gameId);
  }

  // ─────────────────────────────────────
  // 내 경기 목록
  // ─────────────────────────────────────

  async listMyGames(userId: string, query: ListGamesQuery) {
    const { status, cursor, limit } = query;

    const qb = this.gameRepo
      .createQueryBuilder('game')
      .leftJoinAndSelect('game.match', 'match')
      .leftJoinAndSelect('match.requesterProfile', 'rp')
      .leftJoinAndSelect('rp.user', 'rpUser')
      .leftJoinAndSelect('match.opponentProfile', 'op')
      .leftJoinAndSelect('op.user', 'opUser')
      .where('(rp.userId = :userId OR op.userId = :userId)', { userId });

    if (status) qb.andWhere('game.resultStatus = :status', { status });
    if (cursor) qb.andWhere('game.createdAt < :cursor', { cursor: new Date(cursor) });

    qb.orderBy('game.createdAt', 'DESC').take(limit + 1);

    const games = await qb.getMany();

    const hasMore = games.length > limit;
    const items = hasMore ? games.slice(0, limit) : games;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items, nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // ─────────────────────────────────────
  // 자동 결과 확정: 양측 미입력 → 무승부 처리 (worker용)
  // ─────────────────────────────────────

  async resolveGameAsDraw(gameId: string): Promise<void> {
    const game = await this.gameRepo.findOne({
      where: { id: gameId },
      relations: {
        match: {
          requesterProfile: { user: true } as any,
          opponentProfile: { user: true } as any,
        } as any,
      } as any,
    });

    if (!game) {
      throw new AppError(ErrorCode.NOT_FOUND, 404, `Game not found: ${gameId}`);
    }

    // 이미 처리된 경우 스킵
    if (!['PENDING', 'PROOF_UPLOADED'].includes(game.resultStatus)) return;

    const match = game.match as any;

    // winnerProfileId = null → DRAW
    await this.gameRepo.update(gameId, { winnerProfileId: null });

    const applied = await this.applyEloChanges(gameId, { ...game, winnerProfileId: null }, match);

    // applyEloChanges가 false(=이미 다른 인스턴스에서 처리)면 알림/메시지 스킵
    if (applied === false) return;

    // 경기 완료 → COMPLETED 상태 실시간 전달 (WS 먼저, push 나중)
    try {
      await redis.publish('match_lifecycle', JSON.stringify({
        event: 'MATCH_STATUS_CHANGED',
        matchId: match.id,
        data: { matchId: match.id, status: 'COMPLETED', gameId },
      }));
    } catch (pubErr) {
      console.warn('[AutoResolve] match_lifecycle publish failed:', pubErr);
    }

    // 양쪽 유저에게 MATCH_COMPLETED 알림
    if (this.notificationService) {
      const message = '양측 모두 결과를 입력하지 않아 무승부로 자동 처리되었습니다.';
      await this.notificationService.sendBulk([
        {
          userId: (match.requesterProfile as any).userId,
          type: 'MATCH_COMPLETED',
          title: '경기 자동 완료',
          body: message,
          data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
        },
        {
          userId: (match.opponentProfile as any).userId,
          type: 'MATCH_COMPLETED',
          title: '경기 자동 완료',
          body: message,
          data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
        },
      ]);
    }

    console.info(`[AutoResolve] Game ${gameId} resolved as DRAW (3-day timeout)`);
  }

  // ─────────────────────────────────────
  // 자동 결과 확정: 한쪽만 제출 → 제출된 결과 채택 (worker용)
  // ─────────────────────────────────────

  async resolveGameWithSingleResult(gameId: string): Promise<void> {
    const game = await this.gameRepo.findOne({
      where: { id: gameId },
      relations: {
        match: {
          requesterProfile: { user: true } as any,
          opponentProfile: { user: true } as any,
        } as any,
      } as any,
    });

    if (!game) {
      throw new AppError(ErrorCode.NOT_FOUND, 404, `Game not found: ${gameId}`);
    }

    const requesterClaim = (game as any).requesterClaimedResult as string | null;
    const opponentClaim = (game as any).opponentClaimedResult as string | null;

    // 양측 모두 제출하지 않은 경우 (이미 resolveGameAsDraw로 처리되어야 함)
    if (!requesterClaim && !opponentClaim) return;

    // 이미 양측 모두 제출된 경우 스킵 (정상 플로우에서 이미 처리)
    if (requesterClaim && opponentClaim) return;

    // 이미 처리된 경우 스킵
    if (!['PENDING', 'PROOF_UPLOADED'].includes(game.resultStatus)) return;

    const match = game.match as any;
    const requesterProfileId = (match.requesterProfile as any).id;
    const opponentProfileId = (match.opponentProfile as any).id;

    // 제출된 결과 기준으로 winnerProfileId 결정
    let winnerProfileId: string | null = null;
    if (requesterClaim === 'WIN') {
      winnerProfileId = requesterProfileId;
    } else if (requesterClaim === 'LOSS') {
      winnerProfileId = opponentProfileId;
    } else if (opponentClaim === 'WIN') {
      winnerProfileId = opponentProfileId;
    } else if (opponentClaim === 'LOSS') {
      winnerProfileId = requesterProfileId;
    }
    // DRAW → winnerProfileId = null

    await this.gameRepo.update(gameId, { winnerProfileId });

    const applied = await this.applyEloChanges(gameId, { ...game, winnerProfileId }, match);

    // applyEloChanges가 false(=이미 다른 인스턴스에서 처리)면 알림/메시지 스킵
    if (applied === false) return;

    // 채팅방에 자동 확정 시스템 메시지 전송 + WS broadcast
    if (match.chatRoomId) {
      const messageRepo = this.dataSource.getRepository(Message);
      const chatRoomRepo = this.dataSource.getRepository(ChatRoom);
      const sysMsg = messageRepo.create({
        chatRoomId: match.chatRoomId,
        senderId: (match.requesterProfile as any).userId,
        messageType: MessageType.SYSTEM,
        content: '상대방이 3분 내에 결과를 입력하지 않아 제출된 결과로 경기가 자동 확정되었습니다.',
        extraData: { type: 'GAME_AUTO_RESOLVED' },
      });
      const savedMsg = await messageRepo.save(sysMsg);
      await chatRoomRepo.update(match.chatRoomId, { lastMessageAt: new Date() });

      // 채팅방에 실시간 시스템 메시지 브로드캐스트 (직접 emit)
      const autoResolveMsgData = {
        id: savedMsg.id,
        roomId: match.chatRoomId,
        sender: null,
        content: savedMsg.content,
        messageType: 'SYSTEM',
        extraData: savedMsg.extraData,
        readAt: null,
        createdAt: savedMsg.createdAt,
      };
      try {
        const io = (global as any).__io;
        if (io) {
          io.to(`room:${match.chatRoomId}`).emit('NEW_MESSAGE', autoResolveMsgData);
        } else {
          await redis.publish('chat_room_message', JSON.stringify({ roomId: match.chatRoomId, message: autoResolveMsgData }));
        }
      } catch (pubErr) {
        console.warn('[AutoResolve] chat message broadcast failed:', pubErr);
      }
    }

    // 경기 완료 → COMPLETED 상태 실시간 전달 (WS 먼저, push 나중)
    try {
      await redis.publish('match_lifecycle', JSON.stringify({
        event: 'MATCH_STATUS_CHANGED',
        matchId: match.id,
        data: { matchId: match.id, status: 'COMPLETED', gameId },
      }));
    } catch (pubErr) {
      console.warn('[AutoResolve] match_lifecycle publish failed:', pubErr);
    }

    // 양쪽 유저에게 MATCH_COMPLETED 알림
    if (this.notificationService) {
      const message = '상대방 미입력으로 경기 결과가 자동 확정되었습니다. 점수가 반영되었습니다.';
      await this.notificationService.sendBulk([
        {
          userId: (match.requesterProfile as any).userId,
          type: 'MATCH_COMPLETED',
          title: '경기 자동 완료',
          body: message,
          data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
        },
        {
          userId: (match.opponentProfile as any).userId,
          type: 'MATCH_COMPLETED',
          title: '경기 자동 완료',
          body: message,
          data: { matchId: match.id, gameId, deepLink: `/matches/${match.id}` },
        },
      ]);
    }

    console.info(`[AutoResolve] Game ${gameId} resolved with single-side result (3-min timeout)`);
  }

  // ─────────────────────────────────────
  // Private: 경기 조회 + 참여자 검증
  // ─────────────────────────────────────

  private async getGameWithAuth(userId: string, gameId: string) {
    const game = await this.gameRepo.findOne({
      where: { id: gameId },
      relations: {
        match: {
          requesterProfile: { user: true } as any,
          opponentProfile: { user: true } as any,
        } as any,
      } as any,
    });

    if (!game) {
      throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);
    }

    const isParticipant =
      (game.match.requesterProfile as any).userId === userId ||
      (game.match.opponentProfile as any).userId === userId;

    if (!isParticipant) {
      throw AppError.forbidden(ErrorCode.GAME_NOT_PARTICIPANT);
    }

    return game;
  }

  async addProofImages(userId: string, gameId: string, imageUrls: string[]): Promise<void> {
    const game = await this.gameRepo.findOne({ where: { id: gameId } });
    if (!game) throw AppError.notFound(ErrorCode.GAME_NOT_FOUND);

    const existing = game.proofImageUrls ?? [];
    const merged = [...existing, ...imageUrls].slice(0, 10); // 최대 10장

    await this.gameRepo.update(gameId, { proofImageUrls: merged });
  }
}
