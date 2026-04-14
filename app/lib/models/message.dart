/// 채팅 메시지 모델
class Message {
  final String id;
  final String chatRoomId;
  final String senderId;
  final String senderNickname;
  final String? senderProfileImageUrl;
  final String messageType; // TEXT | IMAGE | SYSTEM | LOCATION
  final String content;
  final String? imageUrl;
  final Map<String, dynamic>? extraData;
  final bool isRead;
  final DateTime? readAt;
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
    this.extraData,
    required this.isRead,
    this.readAt,
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
      extraData: json['extraData'] != null
          ? Map<String, dynamic>.from(json['extraData'] as Map)
          : null,
      isRead: json['isRead'] as bool? ?? false,
      readAt: json['readAt'] != null
          ? DateTime.parse(json['readAt'] as String)
          : null,
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
        'extraData': extraData,
        'isRead': isRead,
        'readAt': readAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  /// readAt 필드를 업데이트한 복사본 반환
  Message copyWithReadAt(DateTime readAt) {
    return Message(
      id: id,
      chatRoomId: chatRoomId,
      senderId: senderId,
      senderNickname: senderNickname,
      senderProfileImageUrl: senderProfileImageUrl,
      messageType: messageType,
      content: content,
      imageUrl: imageUrl,
      extraData: extraData,
      isRead: true,
      readAt: readAt,
      createdAt: createdAt,
    );
  }

  bool get isText => messageType == 'TEXT';
  bool get isImage => messageType == 'IMAGE';
  bool get isSystem => messageType == 'SYSTEM';
  bool get isLocation => messageType == 'LOCATION';
  bool get isVerificationCode => messageType == 'VERIFICATION_CODE';

  /// 위치 메시지 데이터 파싱
  LocationData? get locationData {
    if (!isLocation || extraData == null) return null;
    try {
      final lat = (extraData!['latitude'] as num?)?.toDouble();
      final lng = (extraData!['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LocationData(
        latitude: lat,
        longitude: lng,
        address: extraData!['address'] as String?,
        placeName: extraData!['placeName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 소켓 수신 메시지로부터 생성
  factory Message.fromSocketData(Map<String, dynamic> data) {
    final rawSender = data['sender'];
    final sender = rawSender is Map ? Map<String, dynamic>.from(rawSender) : null;
    return Message(
      id: data['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      chatRoomId: data['roomId'] as String? ?? '',
      senderId: sender?['id'] as String? ??
          data['senderId'] as String? ?? '',
      senderNickname: sender?['nickname'] as String? ?? '',
      senderProfileImageUrl: sender?['profileImageUrl'] as String?,
      messageType: data['messageType'] as String? ?? 'TEXT',
      content: data['content'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      extraData: data['extraData'] != null
          ? Map<String, dynamic>.from(data['extraData'] as Map)
          : null,
      isRead: data['readAt'] != null,
      readAt: data['readAt'] != null
          ? DateTime.parse(data['readAt'] as String)
          : null,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// 위치 메시지 데이터 클래스
class LocationData {
  final double latitude;
  final double longitude;
  final String? address;
  final String? placeName;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.address,
    this.placeName,
  });
}
