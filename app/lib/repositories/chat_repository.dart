import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/local/daos/chat_dao.dart';
import '../data/local/cache_ttl_helper.dart';
import '../data/local/database_provider.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';

class ChatRepository {
  final ApiClient _api;
  final ChatDao _dao;
  final CacheTtlHelper _cache;

  static const _roomsCacheKey = 'chat_rooms';

  const ChatRepository(this._api, this._dao, this._cache);

  // ─── 채팅방 목록 (SWR) ───────────────────────────────

  /// 채팅방 목록 Stream
  Stream<List<ChatRoom>> watchChatRooms() => _dao.watchChatRooms();

  /// 로컬 채팅방 목록
  Future<List<ChatRoom>> getChatRoomsLocal() => _dao.getChatRooms();

  /// 로컬에 채팅방 캐시가 있는지
  Future<bool> hasChatRoomsCache() async {
    final count = await _dao.getChatRoomCount();
    return count > 0;
  }

  /// 채팅방 목록 API 조회 → 로컬 저장
  Future<List<ChatRoom>> fetchAndCacheChatRooms() async {
    final response = await _api.get('/chat-rooms');
    final data = response['data'] as List<dynamic>;
    final rooms = data.map((e) => ChatRoom.fromJson(e as Map<String, dynamic>)).toList();
    await _dao.upsertChatRooms(rooms);
    await _cache.update(_roomsCacheKey);
    return rooms;
  }

  /// TTL 만료 시만 API 호출
  Future<void> refreshRoomsIfStale() async {
    final hasCache = await hasChatRoomsCache();
    if (!hasCache) {
      await fetchAndCacheChatRooms();
      return;
    }

    final expired = await _cache.isExpired(_roomsCacheKey, CacheTtlHelper.chatRoomsTtl);
    if (!expired) return;

    try {
      await fetchAndCacheChatRooms();
    } catch (e) {
      debugPrint('[ChatRepo] 채팅방 갱신 실패: $e');
    }
  }

  /// 채팅방 lastMessage 로컬 업데이트 (소켓 이벤트용)
  Future<void> updateLocalLastMessage(
    String roomId, {
    required String content,
    required String messageType,
    required DateTime createdAt,
    int? unreadCount,
  }) async {
    await _dao.updateLastMessage(
      roomId,
      content: content,
      messageType: messageType,
      createdAt: createdAt,
      unreadCount: unreadCount,
    );
  }

  // ─── 메시지 (SWR) ───────────────────────────────────

  /// 특정 방의 메시지 Stream
  Stream<List<Message>> watchMessages(String roomId) => _dao.watchMessages(roomId);

  /// 로컬 메시지 목록
  Future<List<Message>> getMessagesLocal(String roomId) => _dao.getMessages(roomId);

  /// 로컬 메시지 개수
  Future<int> getMessageCount(String roomId) => _dao.getMessageCount(roomId);

  /// API에서 메시지 조회 → 로컬 저장
  Future<MessageResult> fetchAndCacheMessages(
    String roomId, {
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/chat-rooms/$roomId/messages',
      queryParameters: {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final data = response['data'] as List<dynamic>;
    final meta = response['meta'] as Map<String, dynamic>?;

    final messages = data
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();

    // 로컬 DB에 저장
    await _dao.upsertMessages(messages);

    return MessageResult(
      messages: messages,
      nextCursor: meta?['cursor'] as String?,
      hasMore: meta?['hasMore'] as bool? ?? false,
    );
  }

  /// 소켓 수신 메시지 → 로컬 DB 저장
  Future<void> saveSocketMessage(Message message) async {
    await _dao.upsertMessage(message);
  }

  /// HTTP 폴백 메시지 전송
  Future<Message> sendMessage(
    String roomId, {
    required String content,
    String messageType = 'TEXT',
  }) async {
    final response = await _api.post(
      '/chat-rooms/$roomId/messages',
      body: {
        'messageType': messageType,
        'content': content,
      },
    );
    final message = Message.fromJson(response['data'] as Map<String, dynamic>);
    // 로컬 DB에도 저장
    await _dao.upsertMessage(message);
    return message;
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final cache = ref.watch(cacheTtlHelperProvider);
  return ChatRepository(ApiClient.instance, ChatDao(db), cache);
});
