/// 채팅 메시지 모델
class Message {
  final String id;
  final String chatRoomId;
  final String senderId;
  final String senderNickname;
  final String? senderProfileImageUrl;
  final String messageType; // TEXT | IMAGE | SYSTEM
  final String content;
  final String? imageUrl;
  final bool isRead;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.senderNickname,
    this.senderProfileImageUrl,
    required this.messageType,
    required this.content,
    this.imageUrl,
    required this.isRead,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return Message(
      id: json['id'] as String,
      chatRoomId: json['chatRoomId'] as String? ??
          json['roomId'] as String? ?? '',
      senderId: sender?['id'] as String? ??
          json['senderId'] as String? ?? '',
      senderNickname: sender?['nickname'] as String? ?? '',
      senderProfileImageUrl: sender?['profileImageUrl'] as String?,
      messageType: json['messageType'] as String? ?? 'TEXT',
      content: json['content'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatRoomId': chatRoomId,
        'senderId': senderId,
        'senderNickname': senderNickname,
        'senderProfileImageUrl': senderProfileImageUrl,
        'messageType': messageType,
        'content': content,
        'imageUrl': imageUrl,
        'isRead': isRead,
        'createdAt': createdAt.toIso8601String(),
      };

  bool get isText => messageType == 'TEXT';
  bool get isImage => messageType == 'IMAGE';
  bool get isSystem => messageType == 'SYSTEM';

  /// 소켓 수신 메시지로부터 생성
  factory Message.fromSocketData(Map<String, dynamic> data) {
    final sender = data['sender'] as Map<String, dynamic>?;
    return Message(
      id: data['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      chatRoomId: data['roomId'] as String? ?? '',
      senderId: sender?['id'] as String? ?? '',
      senderNickname: sender?['nickname'] as String? ?? '',
      senderProfileImageUrl: sender?['profileImageUrl'] as String?,
      messageType: data['messageType'] as String? ?? 'TEXT',
      content: data['content'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      isRead: false,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
