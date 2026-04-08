import { AppDataSource } from '../../config/database.js';
import { ChatRoom } from '../../entities/chat-room.entity.js';
import { Match } from '../../entities/match.entity.js';
import { Message } from '../../entities/message.entity.js';
import { AppError, ErrorCode } from '../../shared/errors/app-error.js';

export class ChatService {
  private chatRoomRepo = AppDataSource.getRepository(ChatRoom);
  private matchRepo = AppDataSource.getRepository(Match);
  private messageRepo = AppDataSource.getRepository(Message);

  // ─────────────────────────────────────
  // 채팅방 목록 조회
  // ─────────────────────────────────────

  async getChatRooms(userId: string) {
    // 사용자가 참여한 매치의 채팅방 조회
    // Match 엔티티가 chatRoomId를 외래키로 가지므로, Match를 통해 조회
    const matches = await this.matchRepo.find({
      where: [
        { requesterProfile: { userId } },
        { opponentProfile: { userId } },
      ],
      relations: {
        requesterProfile: { user: true },
        opponentProfile: { user: true },
      },
    });

    if (matches.length === 0) return [];

    const chatRoomIds = matches
      .map((m) => m.chatRoomId)
      .filter((id): id is string => id !== null);

    if (chatRoomIds.length === 0) return [];

    // 채팅방 목록 조회 (status 필터 + 최신순 정렬)
    const rooms = await this.chatRoomRepo
      .createQueryBuilder('room')
      .where('room.id IN (:...ids)', { ids: chatRoomIds })
      .andWhere("room.status != 'ARCHIVED'")
      .orderBy('room.last_message_at', 'DESC', 'NULLS LAST')
      .getMany();

    // 마지막 메시지를 채팅방별로 조회
    const lastMessages = await Promise.all(
      chatRoomIds.map((id) =>
        this.messageRepo.findOne({
          where: { chatRoomId: id, isDeleted: false },
          order: { createdAt: 'DESC' },
        }),
      ),
    );

    const lastMessageMap = new Map<string, Message | null>();
    chatRoomIds.forEach((id, idx) => lastMessageMap.set(id, lastMessages[idx] ?? null));

    const matchByChatRoomId = new Map<string, typeof matches[0]>();
    for (const match of matches) {
      if (match.chatRoomId) {
        matchByChatRoomId.set(match.chatRoomId, match);
      }
    }

    return rooms
      .map((room) => {
        const match = matchByChatRoomId.get(room.id);
        if (!match) return null;

        const isRequester = match.requesterProfile.userId === userId;
        const opponent = isRequester ? match.opponentProfile : match.requesterProfile;
        const lastMessage = lastMessageMap.get(room.id) ?? null;

        return {
          id: room.id,
          matchId: room.matchId,
          status: room.status,
          opponent: {
            id: opponent.user.id,
            nickname: opponent.user.nickname,
            profileImageUrl: opponent.user.profileImageUrl,
          },
          lastMessage: lastMessage
            ? {
                content:
                  lastMessage.messageType === 'IMAGE'
                    ? '사진을 보냈습니다'
                    : lastMessage.content,
                createdAt: lastMessage.createdAt,
              }
            : null,
          lastMessageAt: room.lastMessageAt,
          createdAt: room.createdAt,
        };
      })
      .filter(Boolean);
  }

  // ─────────────────────────────────────
  // 메시지 목록 (cursor 기반 페이지네이션)
  // ─────────────────────────────────────

  async getMessages(
    userId: string,
    roomId: string,
    opts: { cursor?: string; after?: string; limit?: number } = {},
  ) {
    const { cursor, after, limit = 50 } = opts;

    // 채팅방 참여자 확인
    await this.validateRoomParticipant(userId, roomId);

    const queryBuilder = this.messageRepo
      .createQueryBuilder('message')
      .leftJoinAndSelect('message.sender', 'sender')
      .where('message.chat_room_id = :roomId', { roomId })
      .andWhere('message.is_deleted = false');

    if (cursor) {
      queryBuilder.andWhere('message.created_at < :cursor', { cursor: new Date(cursor) });
    }

    // after: 특정 시간 이후 메시지만 조회 (증분 fetch용)
    if (after) {
      queryBuilder.andWhere('message.created_at > :after', { after: new Date(after) });
    }

    const messages = await queryBuilder
      .orderBy('message.created_at', 'DESC')
      .take(limit + 1)
      .getMany();

    const hasMore = messages.length > limit;
    const items = hasMore ? messages.slice(0, limit) : messages;
    const nextCursor = hasMore ? items[items.length - 1].createdAt.toISOString() : null;

    return { items: items.reverse(), nextCursor, hasMore };
  }

  // ─────────────────────────────────────
  // HTTP Fallback: 메시지 전송
  // ─────────────────────────────────────

  async sendMessage(
    userId: string,
    roomId: string,
    dto: {
      messageType: 'TEXT' | 'IMAGE' | 'SYSTEM' | 'SCHEDULE_PROPOSAL';
      content?: string;
      imageUrl?: string;
      extraData?: Record<string, unknown>;
    },
  ) {
    await this.validateRoomParticipant(userId, roomId);

    if (dto.messageType === 'TEXT' && dto.content) {
      if (dto.content.length > 500) {
        throw AppError.badRequest(ErrorCode.CHAT_MESSAGE_TOO_LONG);
      }
    }

    const message = this.messageRepo.create({
      chatRoomId: roomId,
      senderId: userId,
      messageType: dto.messageType as any,
      content: dto.content,
      imageUrl: dto.imageUrl,
      extraData: dto.extraData ?? {},
    });

    const saved = await this.messageRepo.save(message);

    // sender 정보 로드
    const withSender = await this.messageRepo.findOne({
      where: { id: saved.id },
      relations: { sender: true },
    });

    // 채팅방 lastMessageAt 업데이트
    await this.chatRoomRepo.update(roomId, { lastMessageAt: saved.createdAt });

    return withSender!;
  }

  // ─────────────────────────────────────
  // 채팅방 참여자 검증
  // ─────────────────────────────────────

  async validateRoomParticipant(userId: string, roomId: string): Promise<void> {
    const room = await this.chatRoomRepo.findOne({
      where: { id: roomId },
    });

    if (!room) {
      throw AppError.notFound(ErrorCode.CHAT_ROOM_NOT_FOUND);
    }

    if (room.status === 'BLOCKED' as any) {
      throw AppError.forbidden(ErrorCode.CHAT_ROOM_BLOCKED);
    }

    // Match를 통해 참여자 확인 (Match가 chatRoomId를 외래키로 가짐)
    const match = await this.matchRepo.findOne({
      where: { chatRoomId: roomId },
      relations: {
        requesterProfile: true,
        opponentProfile: true,
      },
    });

    if (match) {
      const participantIds = [
        match.requesterProfile.userId,
        match.opponentProfile.userId,
      ];

      if (!participantIds.includes(userId)) {
        throw AppError.forbidden(ErrorCode.CHAT_NOT_PARTICIPANT);
      }
    }
  }
}
