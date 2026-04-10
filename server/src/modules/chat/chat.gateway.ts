import { Server, Socket } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import Redis from 'ioredis';
import { verifyAccessToken } from '../../shared/utils/jwt.js';
import { AppDataSource } from '../../config/database.js';
import { User } from '../../entities/user.entity.js';
import { ChatRoom } from '../../entities/chat-room.entity.js';
import { Match } from '../../entities/match.entity.js';
import { Message } from '../../entities/message.entity.js';
import { ChatService } from './chat.service.js';

// ─────────────────────────────────────
// 타입 정의
// ─────────────────────────────────────

interface JoinRoomData {
  roomId: string;
}

interface SendMessageData {
  roomId: string;
  content: string;
  messageType: 'TEXT' | 'IMAGE' | 'LOCATION';
  extraData?: Record<string, unknown>;
}

interface TypingData {
  roomId: string;
}

// ─────────────────────────────────────
// 읽음 처리 헬퍼 (JOIN_ROOM / MARK_READ 공용)
// ─────────────────────────────────────

async function _markReadAndNotify(
  roomId: string,
  userId: string,
  io: Server,
  chatService: ChatService,
): Promise<void> {
  const readMessageIds = await chatService.markMessagesRead(userId, roomId);
  if (readMessageIds.length === 0) return;

  // 채팅방의 모든 소켓(상대방 포함)에 읽음 이벤트 전송
  // 각 앱 클라이언트는 readByUserId를 통해 자신이 보낸 메시지인지 판단
  io.to(`room:${roomId}`).emit('MESSAGES_READ', {
    roomId,
    readByUserId: userId,
    messageIds: readMessageIds,
  });
}

// ─────────────────────────────────────
// 소켓 게이트웨이 설정
// PRD 섹션 4.10.6 상세 설계 기반
// ─────────────────────────────────────

export function setupSocketGateway(io: Server, redis: Redis): void {
  // Redis Adapter 설정 (멀티 서버 인스턴스 간 이벤트 동기화)
  const pubClient = redis.duplicate();
  const subClient = redis.duplicate();
  io.adapter(createAdapter(pubClient, subClient));

  const userRepo = AppDataSource.getRepository(User);
  const chatRoomRepo = AppDataSource.getRepository(ChatRoom);
  const matchRepo = AppDataSource.getRepository(Match);
  const messageRepo = AppDataSource.getRepository(Message);
  const chatService = new ChatService();

  // ─── 인증 미들웨어 ───
  io.use(async (socket: Socket, next) => {
    try {
      const token =
        (socket.handshake.auth as Record<string, string>)?.token ??
        (socket.handshake.query?.token as string);

      if (!token) {
        return next(new Error('NO_TOKEN'));
      }

      const payload = await verifyAccessToken(token);

      // 사용자 상태 확인
      const user = await userRepo.findOne({
        where: { id: payload.userId },
        select: { id: true, status: true },
      });

      if (!user || user.status !== 'ACTIVE') {
        return next(new Error('UNAUTHORIZED'));
      }

      socket.data.userId = payload.userId;
      next();
    } catch {
      next(new Error('UNAUTHORIZED'));
    }
  });

  // ─── 연결 핸들러 ───
  io.on('connection', async (socket: Socket) => {
    const userId = socket.data.userId as string;

    // 사용자 전용 룸 자동 조인 (알림 수신용)
    await socket.join(`user:${userId}`);

    // 온라인 상태 기록
    await redis.sadd('online_users', userId);
    await redis.set(`user_socket:${userId}`, socket.id, 'EX', 86400);

    console.info(`[WS] Connected: ${userId} (${socket.id})`);

    // ─── 채팅방 입장 ───
    socket.on('JOIN_ROOM', async (data: JoinRoomData): Promise<void> => {
      try {
        const room = await chatRoomRepo.findOne({
          where: { id: data.roomId },
        });

        if (!room) {
          socket.emit('ERROR', { code: 'ROOM_NOT_FOUND', message: '채팅방을 찾을 수 없습니다.' });
          return;
        }

        if (room.status === 'BLOCKED' as any) {
          socket.emit('ERROR', { code: 'ROOM_BLOCKED', message: '차단된 채팅방입니다.' });
          return;
        }

        // Match를 통해 참여자 확인 (Match가 chatRoomId를 외래키로 가짐)
        const match = await matchRepo.findOne({
          where: { chatRoomId: data.roomId },
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
            socket.emit('ERROR', { code: 'FORBIDDEN', message: '접근 권한이 없습니다.' });
            return;
          }
        }

        await socket.join(`room:${data.roomId}`);

        // 현재 활성 채팅방 기록 (푸시 스킵 판단용)
        await redis.set(`user_active_room:${userId}`, data.roomId, 'EX', 3600);

        socket.emit('ROOM_JOINED', { roomId: data.roomId });

        // 입장 시 자동으로 읽음 처리
        await _markReadAndNotify(data.roomId, userId, io, chatService);
      } catch (err) {
        console.error('[WS] JOIN_ROOM error:', err);
        socket.emit('ERROR', { code: 'INTERNAL_ERROR', message: '오류가 발생했습니다.' });
      }
    });

    // ─── 채팅방 퇴장 ───
    socket.on('LEAVE_ROOM', async (data: JoinRoomData) => {
      await socket.leave(`room:${data.roomId}`);
      await redis.del(`user_active_room:${userId}`);
      socket.emit('ROOM_LEFT', { roomId: data.roomId });
    });

    // ─── 메시지 전송 ───
    socket.on('SEND_MESSAGE', async (data: SendMessageData): Promise<void> => {
      try {
        // LOCATION 타입은 content 없이 extraData로 전송
        if (!data.roomId || (data.messageType !== 'LOCATION' && !data.content)) {
          socket.emit('ERROR', { code: 'INVALID_DATA', message: '필수 데이터가 없습니다.' });
          return;
        }

        if (data.messageType === 'TEXT' && data.content.length > 500) {
          socket.emit('ERROR', { code: 'MESSAGE_TOO_LONG', message: '메시지는 최대 500자입니다.' });
          return;
        }

        // LOCATION 타입: extraData 검증
        if (data.messageType === 'LOCATION') {
          const extra = data.extraData ?? {};
          if (!extra.latitude || !extra.longitude) {
            socket.emit('ERROR', { code: 'INVALID_DATA', message: '위치 데이터가 없습니다.' });
            return;
          }
        }

        // DB 저장
        const newMessage = messageRepo.create({
          chatRoomId: data.roomId,
          senderId: userId,
          messageType: data.messageType as any,
          content: data.messageType === 'LOCATION' ? '위치를 공유했습니다' : data.content,
          extraData: data.extraData ?? {},
        });
        const savedMessage = await messageRepo.save(newMessage);

        // sender 정보 로드
        const message = await messageRepo.findOne({
          where: { id: savedMessage.id },
          relations: { sender: true },
        });

        if (!message) {
          throw new Error('Failed to load saved message');
        }

        // 채팅방 lastMessageAt 업데이트
        await chatRoomRepo.update(data.roomId, { lastMessageAt: savedMessage.createdAt });

        // 같은 채팅방의 모든 소켓에 실시간 전달
        io.to(`room:${data.roomId}`).emit('NEW_MESSAGE', {
          id: message.id,
          roomId: data.roomId,
          sender: message.sender,
          content: message.content,
          messageType: message.messageType,
          extraData: message.extraData,
          readAt: message.readAt,
          createdAt: message.createdAt,
        });

        // 상대방에게 알림 발송
        const match = await matchRepo.findOne({
          where: { chatRoomId: data.roomId },
          relations: {
            requesterProfile: true,
            opponentProfile: true,
          },
        });

        if (match) {
          const opponentUserId =
            match.requesterProfile.userId === userId
              ? match.opponentProfile.userId
              : match.requesterProfile.userId;

          const notifType =
            data.messageType === 'IMAGE'
              ? 'CHAT_IMAGE'
              : data.messageType === 'LOCATION'
              ? 'CHAT_LOCATION'
              : 'CHAT_MESSAGE';
          const notifBody =
            data.messageType === 'IMAGE'
              ? '사진을 보냈습니다'
              : data.messageType === 'LOCATION'
              ? '위치를 공유했습니다'
              : data.content.substring(0, 100);

          // socket.io를 통해 알림 전송 (user:${opponentUserId} 룸)
          io.to(`user:${opponentUserId}`).emit('notification', {
            type: notifType,
            title: message.sender.nickname,
            body: notifBody,
            data: {
              roomId: data.roomId,
              senderId: userId,
              deepLink: `/chat/${data.roomId}`,
            },
            createdAt: new Date().toISOString(),
          });

          // FCM 푸시는 BullMQ 큐에 넣음 (NotificationService가 처리)
          // 직접 import하면 순환 참조가 생길 수 있으므로 Redis pub/sub 활용
          await redis.publish(
            'push_notification',
            JSON.stringify({
              userId: opponentUserId,
              type: notifType,
              title: message.sender.nickname,
              body: notifBody,
              data: {
                roomId: data.roomId,
                senderId: userId,
                deepLink: `/chat/${data.roomId}`,
              },
              saveToDb: false,
            }),
          );
        }
      } catch (err) {
        console.error('[WS] SEND_MESSAGE error:', err);
        socket.emit('ERROR', { code: 'INTERNAL_ERROR', message: '메시지 전송에 실패했습니다.' });
      }
    });

    // ─── 읽음 처리 ───
    socket.on('MARK_READ', async (data: JoinRoomData): Promise<void> => {
      try {
        await _markReadAndNotify(data.roomId, userId, io, chatService);
      } catch (err) {
        console.error('[WS] MARK_READ error:', err);
      }
    });

    // ─── 타이핑 표시 ───
    socket.on('TYPING', (data: TypingData) => {
      socket.to(`room:${data.roomId}`).emit('USER_TYPING', {
        userId,
        roomId: data.roomId,
      });
    });

    // ─── 연결 해제 ───
    socket.on('disconnect', async () => {
      await redis.srem('online_users', userId);
      await redis.del(`user_socket:${userId}`);
      await redis.del(`user_active_room:${userId}`);
      console.info(`[WS] Disconnected: ${userId}`);
    });

    // ─── 에러 핸들러 ───
    socket.on('error', (err) => {
      console.error(`[WS] Socket error for ${userId}:`, err);
    });
  });
}
