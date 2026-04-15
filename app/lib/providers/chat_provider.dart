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
/// 3. keepAlive 유지하되, 10분 후 자동 만료하여 스테일 데이터 방지
final chatRoomListProvider =
    FutureProvider.autoDispose<List<ChatRoom>>((ref) async {
  // 채팅방 목록은 앱 전역에서 유지하되, 10분 후 자동 만료
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 10), () {
    link.close();
  });

  final repo = ref.read(chatRepositoryProvider);

  final hasCache = await repo.hasChatRoomsCache();

  if (hasCache) {
    unawaited(repo.fetchAndCacheChatRooms().then((rooms) {
      final map = <String, int>{};
      for (final room in rooms) {
        map[room.id] = room.unreadCount;
      }
      ref.read(_unreadMapProvider.notifier).state = map;
    }).catchError((e) {
      debugPrint('[ChatProvider] rooms refresh failed: $e');
    }));
    return repo.getChatRoomsLocal();
  }

  final rooms = await repo.fetchAndCacheChatRooms();
  final map = <String, int>{};
  for (final room in rooms) {
    map[room.id] = room.unreadCount;
  }
  ref.read(_unreadMapProvider.notifier).state = map;
  return rooms;
});

// ─── 읽지 않은 메시지 수 프로바이더 ────────────────────────────

/// roomId → unreadCount 맵 (실시간 업데이트)
final _unreadMapProvider = StateProvider<Map<String, int>>((ref) => {});

/// 서버에서 가져온 unreadCount로 맵 초기화 + 실시간 증감
void syncUnreadFromServer(WidgetRef ref, List<ChatRoom> rooms) {
  final map = <String, int>{};
  for (final room in rooms) {
    map[room.id] = room.unreadCount;
  }
  ref.read(_unreadMapProvider.notifier).state = map;
}

void incrementUnread(dynamic ref, String roomId) {
  final map = Map<String, int>.from((ref as dynamic).read(_unreadMapProvider) as Map);
  map[roomId] = (map[roomId] ?? 0) + 1;
  (ref as dynamic).read(_unreadMapProvider.notifier).state = map;
}

void clearUnread(dynamic ref, String roomId) {
  final map = Map<String, int>.from((ref as dynamic).read(_unreadMapProvider) as Map);
  map[roomId] = 0;
  (ref as dynamic).read(_unreadMapProvider.notifier).state = map;
}

Future<void> refreshUnreadCounts(dynamic ref) async {
  try {
    final repo = (ref as dynamic).read(chatRepositoryProvider) as ChatRepository;
    final rooms = await repo.fetchAndCacheChatRooms();
    final map = <String, int>{};
    for (final room in rooms) {
      map[room.id] = room.unreadCount;
    }
    (ref as dynamic).read(_unreadMapProvider.notifier).state = map;
  } catch (_) {}
}

/// 전체 읽지 않은 메시지 총 수 (바텀 네비 배지용)
final totalUnreadCountProvider = Provider<int>((ref) {
  final map = ref.watch(_unreadMapProvider);
  return map.values.fold<int>(0, (sum, v) => sum + v);
});

/// 특정 채팅방의 읽지 않은 메시지 수
final roomUnreadCountProvider = Provider.family<int, String>((ref, roomId) {
  final map = ref.watch(_unreadMapProvider);
  return map[roomId] ?? 0;
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

    // 채팅방 입장 → 즉시 배지 제거 + 서버 읽음 처리
    // build() 중 다른 provider 수정 불가 → microtask로 지연
    Future.microtask(() => clearUnread(ref, roomId));
    _markAsRead(roomId);

    final repo = ref.read(chatRepositoryProvider);

    // 1) 로컬 DB에서 먼저 로드
    final localMessages = await repo.getMessagesLocal(roomId);

    // 2) API에서 최신 메시지 fetch → DB 저장
    unawaited(_fetchAndMerge(roomId, localMessages).catchError((e) {
      debugPrint('[ChatMessages] fetch failed: $e — will retry in 30s');
      Future.delayed(const Duration(seconds: 30), () {
        if (state.hasValue) {
          _fetchAndMerge(roomId, state.value ?? []).catchError((_) {});
        }
      });
    }));

    // 로컬에 있으면 즉시 반환 + 인증번호 복원
    if (localMessages.isNotEmpty) {
      Future.microtask(() => _restoreReceivedVerificationCode(roomId));
      return localMessages;
    }

    // 없으면 API 조회 대기
    final messages = await _fetchInitialMessages(roomId);
    Future.microtask(() => _restoreReceivedVerificationCode(roomId));
    return messages;
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
      // API에서 새 메시지 fetch 후 인증번호 복원 (오프라인 동안 받은 인증번호 반영)
      _restoreReceivedVerificationCode(roomId);
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

        // VERIFICATION_CODE 메시지 수신 시 provider에 코드 저장 (중복 방지)
        if (message.isVerificationCode) {
          final currentUser = ref.read(currentUserProvider);
          if (message.senderId != currentUser?.id) {
            final code = message.extraData?['verificationCode'] as String?;
            if (code != null && code != ref.read(receivedVerificationCodeProvider(roomId))) {
              ref.read(receivedVerificationCodeProvider(roomId).notifier).state = code;
            }
          }
        }

        // 새 메시지 수신 시 읽음 처리 전송 (내가 현재 채팅방에 있으므로)
        final currentUser = ref.read(currentUserProvider);
        if (message.senderId != currentUser?.id) {
          _markAsRead(roomId);
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
      bool hasChanges = false;
      final updated = currentMessages.map((m) {
        if (idSet.contains(m.id) && m.readAt == null) {
          hasChanges = true;
          return m.copyWithReadAt(readAt);
        }
        return m;
      }).toList();
      if (hasChanges) {
        state = AsyncData(updated);
      }
    });
  }

  /// 기존 메시지에서 상대방이 보낸 인증번호를 찾아 provider에 복원
  void _restoreReceivedVerificationCode(String roomId) {
    final messages = state.valueOrNull;
    if (messages == null) return;
    final currentUser = ref.read(currentUserProvider);
    // 가장 마지막으로 받은 인증번호 메시지를 찾기
    for (int i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.isVerificationCode && m.senderId != currentUser?.id) {
        final code = m.extraData?['verificationCode'] as String?;
        if (code != null && code != ref.read(receivedVerificationCodeProvider(roomId))) {
          ref.read(receivedVerificationCodeProvider(roomId).notifier).state = code;
          break;
        }
      }
    }
  }

  /// 읽음 처리 (소켓 우선, 실패 시 HTTP 폴백)
  Future<void> _markAsRead(String roomId) async {
    if (SocketService.instance.isConnected) {
      SocketService.instance.sendMarkRead(roomId);
    } else {
      try {
        final api = ref.read(chatRepositoryProvider);
        await api.markAsReadHttp(roomId);
      } catch (e) {
        debugPrint('[ChatMessages] markAsRead HTTP failed: $e');
      }
    }
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

  /// 인증번호 메시지 전송
  Future<void> sendVerificationCodeMessage(String verificationCode) async {
    final extraData = <String, dynamic>{
      'verificationCode': verificationCode,
    };

    try {
      SocketService.instance.sendMessage(
        _roomId,
        '인증번호를 전송했습니다',
        type: 'VERIFICATION_CODE',
        extraData: extraData,
      );
    } catch (_) {
      try {
        final repo = ref.read(chatRepositoryProvider);
        final message = await repo.sendMessage(
          _roomId,
          content: '인증번호를 전송했습니다',
          messageType: 'VERIFICATION_CODE',
          extraData: extraData,
        );
        final currentMessages = state.valueOrNull ?? [];
        state = AsyncData([...currentMessages, message]);
      } catch (_) {
        await ref.read(offlineQueueServiceProvider).enqueue(
          action: 'SEND_MESSAGE',
          payload: {
            'roomId': _roomId,
            'content': '인증번호를 전송했습니다',
            'messageType': 'VERIFICATION_CODE',
            'extraData': extraData,
          },
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

/// 수신된 인증번호 저장 provider (roomId → verificationCode)
/// 상대방이 VERIFICATION_CODE 메시지를 보내면 여기에 저장됨
final receivedVerificationCodeProvider =
    StateProvider.family<String?, String>((ref, roomId) => null);

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
