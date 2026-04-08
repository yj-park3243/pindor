import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/chat_rooms_table.dart';
import '../tables/messages_table.dart';
import '../../../models/chat_room.dart' as model;
import '../../../models/message.dart' as model;

part 'chat_dao.g.dart';

@DriftAccessor(tables: [ChatRooms, Messages])
class ChatDao extends DatabaseAccessor<AppDatabase> with _$ChatDaoMixin {
  ChatDao(super.db);

  // ─── 채팅방 목록 ─────────────────────────────────────

  /// 채팅방 목록 Stream (최신 메시지 순)
  Stream<List<model.ChatRoom>> watchChatRooms() {
    return (select(db.chatRooms)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToChatRoom).toList());
  }

  /// 채팅방 목록 1회 조회
  Future<List<model.ChatRoom>> getChatRooms() async {
    final rows = await (select(db.chatRooms)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(_rowToChatRoom).toList();
  }

  /// 채팅방 개수
  Future<int> getChatRoomCount() async {
    final count = countAll();
    final query = selectOnly(db.chatRooms)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 채팅방 배치 upsert
  Future<void> upsertChatRooms(List<model.ChatRoom> rooms) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        db.chatRooms,
        rooms.map((r) => _chatRoomToCompanion(r)).toList(),
      );
    });
  }

  /// 채팅방 단건 upsert
  Future<void> upsertChatRoom(model.ChatRoom room) async {
    await into(db.chatRooms).insertOnConflictUpdate(_chatRoomToCompanion(room));
  }

  /// 채팅방의 lastMessage/unreadCount 업데이트
  Future<void> updateLastMessage(
    String roomId, {
    required String content,
    required String messageType,
    required DateTime createdAt,
    int? unreadCount,
  }) async {
    final lastMsg = jsonEncode({
      'content': content,
      'messageType': messageType,
      'createdAt': createdAt.toIso8601String(),
    });
    await (update(db.chatRooms)..where((t) => t.id.equals(roomId))).write(
      ChatRoomsCompanion(
        lastMessageJson: Value(lastMsg),
        unreadCount: unreadCount != null ? Value(unreadCount) : const Value.absent(),
        cachedAt: Value(DateTime.now()),
      ),
    );
  }

  // ─── 메시지 ──────────────────────────────────────────

  /// 특정 방의 메시지 Stream (시간순)
  Stream<List<model.Message>> watchMessages(String roomId) {
    return (select(db.messages)
          ..where((t) => t.chatRoomId.equals(roomId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_rowToMessage).toList());
  }

  /// 특정 방의 메시지 1회 조회
  Future<List<model.Message>> getMessages(String roomId) async {
    final rows = await (select(db.messages)
          ..where((t) => t.chatRoomId.equals(roomId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_rowToMessage).toList();
  }

  /// 방의 메시지 개수
  Future<int> getMessageCount(String roomId) async {
    final count = countAll();
    final query = selectOnly(db.messages)
      ..addColumns([count])
      ..where(db.messages.chatRoomId.equals(roomId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 방의 가장 최신 메시지 createdAt (증분 fetch용)
  Future<DateTime?> getLatestMessageTime(String roomId) async {
    final query = select(db.messages)
      ..where((t) => t.chatRoomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.createdAt;
  }

  /// 메시지 배치 upsert
  Future<void> upsertMessages(List<model.Message> messages) async {
    if (messages.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(
        db.messages,
        messages.map((m) => _messageToCompanion(m)).toList(),
      );
    });
  }

  /// 메시지 단건 upsert
  Future<void> upsertMessage(model.Message message) async {
    await into(db.messages).insertOnConflictUpdate(_messageToCompanion(message));
  }

  // ─── 변환 헬퍼 ───────────────────────────────────────

  ChatRoomsCompanion _chatRoomToCompanion(model.ChatRoom room) {
    return ChatRoomsCompanion(
      id: Value(room.id),
      matchId: Value(room.matchId),
      opponentJson: Value(jsonEncode({
        'id': room.opponent.id,
        'nickname': room.opponent.nickname,
        'profileImageUrl': room.opponent.profileImageUrl,
        'tier': room.opponent.tier,
      })),
      lastMessageJson: Value(room.lastMessage != null
          ? jsonEncode({
              'content': room.lastMessage!.content,
              'messageType': room.lastMessage!.messageType,
              'createdAt': room.lastMessage!.createdAt.toIso8601String(),
            })
          : null),
      unreadCount: Value(room.unreadCount),
      isActive: Value(room.isActive),
      createdAt: Value(room.createdAt),
      cachedAt: Value(DateTime.now()),
    );
  }

  model.ChatRoom _rowToChatRoom(ChatRoom row) {
    model.ChatRoomParticipant opponent;
    try {
      final json = jsonDecode(row.opponentJson) as Map<String, dynamic>;
      opponent = model.ChatRoomParticipant.fromJson(json);
    } catch (_) {
      opponent = const model.ChatRoomParticipant(id: '', nickname: '');
    }

    model.ChatMessage? lastMessage;
    if (row.lastMessageJson != null) {
      try {
        final json = jsonDecode(row.lastMessageJson!) as Map<String, dynamic>;
        lastMessage = model.ChatMessage.fromJson(json);
      } catch (_) {}
    }

    return model.ChatRoom(
      id: row.id,
      matchId: row.matchId,
      opponent: opponent,
      lastMessage: lastMessage,
      unreadCount: row.unreadCount,
      isActive: row.isActive,
      createdAt: row.createdAt,
    );
  }

  MessagesCompanion _messageToCompanion(model.Message m) {
    return MessagesCompanion(
      id: Value(m.id),
      chatRoomId: Value(m.chatRoomId),
      senderId: Value(m.senderId),
      senderNickname: Value(m.senderNickname),
      senderProfileImageUrl: Value(m.senderProfileImageUrl),
      messageType: Value(m.messageType),
      content: Value(m.content),
      imageUrl: Value(m.imageUrl),
      isRead: Value(m.isRead),
      createdAt: Value(m.createdAt),
    );
  }

  model.Message _rowToMessage(Message row) {
    return model.Message(
      id: row.id,
      chatRoomId: row.chatRoomId,
      senderId: row.senderId,
      senderNickname: row.senderNickname,
      senderProfileImageUrl: row.senderProfileImageUrl,
      messageType: row.messageType,
      content: row.content,
      imageUrl: row.imageUrl,
      isRead: row.isRead,
      createdAt: row.createdAt,
    );
  }
}
