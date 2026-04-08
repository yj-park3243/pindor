/// 앱 알림 모델
class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      data: json['data'] as Map<String, dynamic>? ?? {},
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'data': data,
        'isRead': isRead,
        'createdAt': createdAt.toIso8601String(),
      };

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  /// 딥링크 경로
  String? get deepLink => data['deepLink'] as String?;

  /// 알림 유형별 아이콘 이름
  String get iconName {
    switch (type) {
      case 'MATCH_FOUND':
      case 'MATCH_REQUEST_RECEIVED':
      case 'MATCH_ACCEPTED':
      case 'MATCH_REJECTED':
      case 'MATCH_EXPIRED':
        return 'sports_golf';
      case 'CHAT_MESSAGE':
      case 'CHAT_IMAGE':
        return 'chat_bubble';
      case 'GAME_RESULT_SUBMITTED':
      case 'GAME_RESULT_CONFIRMED':
        return 'check_circle';
      case 'SCORE_UPDATED':
      case 'TIER_CHANGED':
        return 'trending_up';
      case 'COMMUNITY_REPLY':
        return 'forum';
      default:
        return 'notifications';
    }
  }

  String get typeDisplayName {
    switch (type) {
      case 'MATCH_FOUND':
        return '매칭 성사';
      case 'MATCH_REQUEST_RECEIVED':
        return '매칭 요청';
      case 'MATCH_ACCEPTED':
        return '매칭 수락';
      case 'MATCH_REJECTED':
        return '매칭 거절';
      case 'MATCH_EXPIRED':
        return '매칭 만료';
      case 'CHAT_MESSAGE':
        return '새 메시지';
      case 'CHAT_IMAGE':
        return '이미지 수신';
      case 'GAME_RESULT_SUBMITTED':
        return '결과 제출';
      case 'GAME_RESULT_CONFIRMED':
        return '결과 인증';
      case 'SCORE_UPDATED':
        return '점수 변동';
      case 'TIER_CHANGED':
        return '티어 변경';
      case 'RESULT_DEADLINE':
        return '결과 입력 기한';
      case 'COMMUNITY_REPLY':
        return '댓글 알림';
      default:
        return '알림';
    }
  }
}

/// 알림 설정 모델
class NotificationSettings {
  final bool chatMessage;
  final bool matchFound;
  final bool matchRequest;
  final bool gameResult;
  final bool scoreChange;
  final bool communityReply;
  final String? doNotDisturbStart; // "23:00"
  final String? doNotDisturbEnd; // "08:00"

  const NotificationSettings({
    this.chatMessage = true,
    this.matchFound = true,
    this.matchRequest = true,
    this.gameResult = true,
    this.scoreChange = true,
    this.communityReply = true,
    this.doNotDisturbStart,
    this.doNotDisturbEnd,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      chatMessage: json['chatMessage'] as bool? ?? true,
      matchFound: json['matchFound'] as bool? ?? true,
      matchRequest: json['matchRequest'] as bool? ?? true,
      gameResult: json['gameResult'] as bool? ?? true,
      scoreChange: json['scoreChange'] as bool? ?? true,
      communityReply: json['communityReply'] as bool? ?? true,
      doNotDisturbStart: json['doNotDisturbStart'] as String?,
      doNotDisturbEnd: json['doNotDisturbEnd'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'chatMessage': chatMessage,
        'matchFound': matchFound,
        'matchRequest': matchRequest,
        'gameResult': gameResult,
        'scoreChange': scoreChange,
        'communityReply': communityReply,
        'doNotDisturbStart': doNotDisturbStart,
        'doNotDisturbEnd': doNotDisturbEnd,
      };

  NotificationSettings copyWith({
    bool? chatMessage,
    bool? matchFound,
    bool? matchRequest,
    bool? gameResult,
    bool? scoreChange,
    bool? communityReply,
    String? doNotDisturbStart,
    String? doNotDisturbEnd,
  }) {
    return NotificationSettings(
      chatMessage: chatMessage ?? this.chatMessage,
      matchFound: matchFound ?? this.matchFound,
      matchRequest: matchRequest ?? this.matchRequest,
      gameResult: gameResult ?? this.gameResult,
      scoreChange: scoreChange ?? this.scoreChange,
      communityReply: communityReply ?? this.communityReply,
      doNotDisturbStart: doNotDisturbStart ?? this.doNotDisturbStart,
      doNotDisturbEnd: doNotDisturbEnd ?? this.doNotDisturbEnd,
    );
  }
}
