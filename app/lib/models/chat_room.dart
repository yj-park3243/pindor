/// 채팅방 모델
class ChatRoom {
  final String id;
  final String matchId;
  final ChatRoomParticipant opponent;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool isActive;
  final DateTime createdAt;

  const ChatRoom({
    required this.id,
    required this.matchId,
    required this.opponent,
    this.lastMessage,
    required this.unreadCount,
    this.isActive = true,
    required this.createdAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as String,
      matchId: json['matchId'] as String? ?? '',
      opponent: ChatRoomParticipant.fromJson(
          json['opponent'] as Map<String, dynamic>? ?? {}),
      lastMessage: json['lastMessage'] != null
          ? ChatMessage.fromJson(
              json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// 채팅방 참여자 정보
class ChatRoomParticipant {
  final String id;
  final String nickname;
  final String? profileImageUrl;
  final String? tier;

  const ChatRoomParticipant({
    required this.id,
    required this.nickname,
    this.profileImageUrl,
    this.tier,
  });

  factory ChatRoomParticipant.fromJson(Map<String, dynamic> json) {
    return ChatRoomParticipant(
      id: json['id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      profileImageUrl: json['profileImageUrl'] as String?,
      tier: json['tier'] as String?,
    );
  }
}

/// 채팅 메시지 (미리보기용 - 목록에서 사용)
class ChatMessage {
  final String content;
  final DateTime createdAt;
  final String messageType;

  const ChatMessage({
    required this.content,
    required this.createdAt,
    required this.messageType,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      messageType: json['messageType'] as String? ?? 'TEXT',
    );
  }
}
