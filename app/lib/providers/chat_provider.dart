import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../repositories/chat_repository.dart';
import '../core/network/socket_service.dart';
import '../core/offline/offline_queue_service.dart';

/// 채팅방 목록 프로바이더 (SWR 패턴)
///
/// 1. 로컬 DB에서 즉시 반환 (있을 때)
/// 2. 항상 백그라운드로 API 갱신 (새 채팅방 누락 방지)
/// 3. keepAlive 유지하되, 30분 후 자동 만료하여 스테일 데이터 방지
final chatRoomListProvider =
    FutureProvider.autoDispose<List<ChatRoom>>((ref) async {
  // 채팅방 목록은 앱 전역에서 유지하되, 30분 후 자동 만료
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 30), () {
    link.close();
  });

  final repo = ref.read(chatRepositoryProvider);

  final hasCache = await repo.hasChatRoomsCache();

  if (hasCache) {
    // 캐시가 있으면 즉시 로컬 반환 후 항상 백그라운드로 API 갱신
    // (TTL 무관하게 항상 갱신 — 새 채팅방 누락 방지)
    unawaited(repo.fetchAndCacheChatRooms().catchError((e) {
      debugPrint('[ChatProvider] rooms refresh failed: $e');
    }));
    return repo.getChatRoomsLocal();
  }

  return repo.fetchAndCacheChatRooms();
});

// ─── 타이핑 상태 프로바이더 ────────────────────────────

/// roomId별 타이핑 중인 userId 집합을 관리
/// { roomId: Set<userId> }
class SocketTypingNotifier extends AutoDisposeFamilyNotifier<bool, String> {
  Timer? _clearTimer;

  @override
  bool build(String roomId) {
    final subscription = SocketService.instance.onTyping.listen((data) {
      if (data['roomId'] == roomId) {
        state = true;
        _resetTimer();
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      _clearTimer?.cancel();
    });

    return false;
  }

  void _resetTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 3), () {
      state = false;
    });
  }
}

/// roomId별 상대방 타이핑 여부 (true: 타이핑 중)
final socketTypingProvider =
    NotifierProvider.autoDispose.family<SocketTypingNotifier, bool, String>(
  SocketTypingNotifier.new,
);

// ─── 채팅 메시지 Notifier ─────────────────────────────

/// 채팅 메시지 Notifier (SWR 패턴)
///
/// 1. 로컬 DB 메시지 즉시 표시
/// 2. API에서 최신 메시지 fetch → DB 저장 → state 갱신
/// 3. 소켓 수신 메시지 → DB 저장 → state에 추가
class ChatMessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<Message>, String> {
  String? _cursor;
  bool _hasMore = true;
  late String _roomId;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _messagesReadSubscription;

  @override
  Future<List<Message>> build(String roomId) async {
    _roomId = roomId;
    SocketService.instance.joinRoom(roomId);

    ref.onDispose(() {
      _messageSubscription?.cancel();
      _messageSubscription = null;
      _messagesReadSubscription?.cancel();
      _messagesReadSubscription = null;
      SocketService.instance.leaveRoom(roomId);
    });

    _setupSocketListener(roomId);
    _setupMessagesReadListener(roomId);

    // 채팅방 입장 시 읽음 처리 전송
    SocketService.instance.sendMarkRead(roomId);

    final repo = ref.read(chatRepositoryProvider);

    // 1) 로컬 DB에서 먼저 로드
    final localMessages = await repo.getMessagesLocal(roomId);

    // 2) API에서 최신 메시지 fetch → DB 저장
    unawaited(_fetchAndMerge(roomId, localMessages).catchError((e) {
      debugPrint('[ChatMessages] fetch failed: $e');
    }));

    // 로컬에 있으면 즉시 반환
    if (localMessages.isNotEmpty) return localMessages;

    // 없으면 API 조회 대기
    return _fetchInitialMessages(roomId);
  }

  Future<List<Message>> _fetchInitialMessages(String roomId) async {
    final repo = ref.read(chatRepositoryProvider);
    final result = await repo.fetchAndCacheMessages(roomId, limit: 50);
    _cursor = result.nextCursor;
    _hasMore = result.hasMore;
    return result.messages.reversed.toList();
  }

  /// 로컬 데이터 있을 때 백그라운드로 최신 메시지만 fetch
  Future<void> _fetchAndMerge(String roomId, List<Message> existing) async {
    final repo = ref.read(chatRepositoryProvider);
    final result = await repo.fetchAndCacheMessages(roomId, limit: 50);
    _cursor = result.nextCursor;
    _hasMore = result.hasMore;

    // DB에 저장된 상태에서 다시 전체 조회
    final updated = await repo.getMessagesLocal(roomId);
    if (updated.isNotEmpty && state.hasValue) {
      state = AsyncData(updated);
    }
  }

  void _setupSocketListener(String roomId) {
    _messageSubscription?.cancel();
    _messageSubscription = SocketService.instance.onNewMessage.listen((data) async {
      if (data['roomId'] == roomId) {
        final message = Message.fromSocketData(data);

        // 로컬 DB에 저장
        final repo = ref.read(chatRepositoryProvider);
        await repo.saveSocketMessage(message);

        // state에 즉시 추가
        final currentMessages = state.valueOrNull ?? [];
        // 중복 방지
        if (!currentMessages.any((m) => m.id == message.id)) {
          state = AsyncData([...currentMessages, message]);
        }

        // 채팅방 목록의 lastMessage도 업데이트
        await repo.updateLocalLastMessage(
          roomId,
          content: message.content,
          messageType: message.messageType,
          createdAt: message.createdAt,
        );

        // 새 메시지 수신 시 읽음 처리 전송 (내가 현재 채팅방에 있으므로)
        final currentUser = ref.read(currentUserProvider);
        if (message.senderId != currentUser?.id) {
          SocketService.instance.sendMarkRead(roomId);
        }
      }
    });
  }

  /// MESSAGES_READ 이벤트 수신 → 내 메시지 읽음 상태 업데이트
  void _setupMessagesReadListener(String roomId) {
    _messagesReadSubscription?.cancel();
    _messagesReadSubscription =
        SocketService.instance.onMessagesRead.listen((data) async {
      if (data['roomId'] != roomId) return;

      // 내가 읽은 경우는 이미 처리됨, 상대가 읽었을 때만 UI 업데이트
      final currentUser = ref.read(currentUserProvider);
      final readByUserId = data['readByUserId'] as String?;
      if (readByUserId == currentUser?.id) return;

      final rawIds = data['messageIds'];
      if (rawIds == null) return;
      final messageIds = (rawIds as List<dynamic>).cast<String>();
      if (messageIds.isEmpty) return;

      final readAt = DateTime.now();
      final repo = ref.read(chatRepositoryProvider);

      // 로컬 DB 읽음 처리
      await repo.updateMessagesReadAt(messageIds, readAt);

      // state에서 해당 메시지 readAt 업데이트
      final currentMessages = state.valueOrNull;
      if (currentMessages == null) return;

      final idSet = messageIds.toSet();
      final updated = currentMessages.map((m) {
        if (idSet.contains(m.id) && m.readAt == null) {
          return m.copyWithReadAt(readAt);
        }
        return m;
      }).toList();

      state = AsyncData(updated);
    });
  }

  /// 이전 메시지 로드 (스크롤 위로)
  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    try {
      final repo = ref.read(chatRepositoryProvider);
      final result = await repo.fetchAndCacheMessages(
        _roomId,
        cursor: _cursor,
        limit: 50,
      );
      _cursor = result.nextCursor;
      _hasMore = result.hasMore;

      final currentMessages = state.valueOrNull ?? [];
      state = AsyncData([
        ...result.messages.reversed.toList(),
        ...currentMessages,
      ]);
    } catch (e) {
      debugPrint('[ChatMessages] loadMore failed: $e');
    }
  }

  /// 메시지 전송 (소켓 → HTTP → 오프라인 큐 폴백)
  Future<void> sendTextMessage(String content) async {
    try {
      SocketService.instance.sendMessage(_roomId, content, type: 'TEXT');
    } catch (_) {
      try {
        final repo = ref.read(chatRepositoryProvider);
        final message = await repo.sendMessage(
          _roomId,
          content: content,
          messageType: 'TEXT',
        );
        final currentMessages = state.valueOrNull ?? [];
        state = AsyncData([...currentMessages, message]);
      } catch (_) {
        // 오프라인 → 큐에 저장
        await ref.read(offlineQueueServiceProvider).enqueue(
          action: 'SEND_MESSAGE',
          payload: {'roomId': _roomId, 'content': content, 'messageType': 'TEXT'},
        );
      }
    }
  }

  /// 이미지 메시지 전송
  Future<void> sendImageMessage(String imageUrl) async {
    try {
      SocketService.instance.sendMessage(_roomId, imageUrl, type: 'IMAGE');
    } catch (_) {
      try {
        final repo = ref.read(chatRepositoryProvider);
        final message = await repo.sendMessage(
          _roomId,
          content: imageUrl,
          messageType: 'IMAGE',
        );
        final currentMessages = state.valueOrNull ?? [];
        state = AsyncData([...currentMessages, message]);
      } catch (_) {
        await ref.read(offlineQueueServiceProvider).enqueue(
          action: 'SEND_MESSAGE',
          payload: {'roomId': _roomId, 'content': imageUrl, 'messageType': 'IMAGE'},
        );
      }
    }
  }

  /// 위치 메시지 전송
  Future<void> sendLocationMessage({
    required double latitude,
    required double longitude,
    String? address,
    String? placeName,
  }) async {
    final extraData = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
      if (placeName != null) 'placeName': placeName,
    };

    try {
      SocketService.instance.sendMessage(
        _roomId,
        '위치를 공유했습니다',
        type: 'LOCATION',
        extraData: extraData,
      );
    } catch (_) {
      try {
        final repo = ref.read(chatRepositoryProvider);
        final message = await repo.sendMessage(
          _roomId,
          content: '위치를 공유했습니다',
          messageType: 'LOCATION',
          extraData: extraData,
        );
        final currentMessages = state.valueOrNull ?? [];
        state = AsyncData([...currentMessages, message]);
      } catch (_) {
        await ref.read(offlineQueueServiceProvider).enqueue(
          action: 'SEND_MESSAGE',
          payload: {
            'roomId': _roomId,
            'content': '위치를 공유했습니다',
            'messageType': 'LOCATION',
            'extraData': extraData,
          },
        );
      }
    }
  }
}

final chatMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChatMessagesNotifier, List<Message>, String>(
  ChatMessagesNotifier.new,
);

/// 메시지 페이지네이션 결과
class MessageResult {
  final List<Message> messages;
  final String? nextCursor;
  final bool hasMore;

  const MessageResult({
    required this.messages,
    this.nextCursor,
    required this.hasMore,
  });
}
