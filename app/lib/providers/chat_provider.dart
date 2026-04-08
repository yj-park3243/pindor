import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../repositories/chat_repository.dart';
import '../core/network/socket_service.dart';
import '../core/offline/offline_queue_service.dart';

/// 채팅방 목록 프로바이더 (SWR 패턴)
///
/// 1. 로컬 DB에서 즉시 반환 (있을 때)
/// 2. 항상 백그라운드로 API 갱신 (새 채팅방 누락 방지)
final chatRoomListProvider =
    FutureProvider.autoDispose<List<ChatRoom>>((ref) async {
  // 채팅방 목록은 앱 전역에서 유지
  ref.keepAlive();
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

  @override
  Future<List<Message>> build(String roomId) async {
    _roomId = roomId;
    SocketService.instance.joinRoom(roomId);

    ref.onDispose(() {
      _messageSubscription?.cancel();
      _messageSubscription = null;
      SocketService.instance.leaveRoom(roomId);
    });

    _setupSocketListener(roomId);

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
      }
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
