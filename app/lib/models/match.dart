import '../config/sports.dart';

/// 매칭 모델
class Match {
  final String id;
  final String matchRequestId;
  final String sportType;
  final MatchOpponent opponent;
  final String? scheduledDate;
  final String? scheduledTime;
  final String? venueName;
  final String status; // PENDING_ACCEPT | CHAT | CONFIRMED | COMPLETED | CANCELLED | DISPUTED
  final String chatRoomId;
  final String? gameId;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final List<MatchAcceptance>? acceptances;
  final bool isCasual; // true = 친선 게임, false = 랭크 게임
  final String? gameResult; // WIN | LOSS | DRAW (완료된 매칭만)
  final String? pinName; // 매칭 핀 지역명
  final int encounterCount; // 상대와의 이전 만남 횟수
  final String? desiredDate; // 매칭 요청 희망 날짜
  final String? desiredTimeSlot; // 매칭 요청 희망 시간대
  final bool myResultSubmitted; // 내가 결과를 이미 제출했는지
  final int? myScoreChange; // 내 점수 변동 (+28, -15 등)
  final String? myVerificationCode; // 나의 4자리 인증번호

  const Match({
    required this.id,
    required this.matchRequestId,
    required this.sportType,
    required this.opponent,
    this.scheduledDate,
    this.scheduledTime,
    this.venueName,
    required this.status,
    required this.chatRoomId,
    this.gameId,
    this.confirmedAt,
    this.completedAt,
    required this.createdAt,
    this.acceptances,
    this.isCasual = false,
    this.gameResult,
    this.pinName,
    this.encounterCount = 0,
    this.desiredDate,
    this.desiredTimeSlot,
    this.myResultSubmitted = false,
    this.myScoreChange,
    this.myVerificationCode,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] as String,
      matchRequestId: json['matchRequestId'] as String? ?? '',
      sportType: json['sportType'] as String? ?? 'GOLF',
      opponent: MatchOpponent.fromJson(
          json['opponent'] as Map<String, dynamic>? ?? {}),
      scheduledDate: json['scheduledDate'] as String?,
      scheduledTime: json['scheduledTime'] as String?,
      venueName: json['venueName'] as String?,
      status: json['status'] as String? ?? 'CHAT',
      chatRoomId: json['chatRoomId'] as String? ?? '',
      gameId: json['gameId'] as String?,
      confirmedAt: json['confirmedAt'] != null
          ? DateTime.parse(json['confirmedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      acceptances: _parseAcceptances(json),
      isCasual: json['isCasual'] as bool? ?? false,
      gameResult: json['gameResult'] as String?,
      pinName: json['pinName'] as String?,
      encounterCount: json['encounterCount'] as int? ?? 0,
      desiredDate: json['desiredDate'] as String?,
      desiredTimeSlot: json['desiredTimeSlot'] as String?,
      myResultSubmitted: json['myResultSubmitted'] as bool? ?? false,
      myScoreChange: json['myScoreChange'] as int?,
      myVerificationCode: json['myVerificationCode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'matchRequestId': matchRequestId,
        'sportType': sportType,
        'opponent': opponent.toJson(),
        'scheduledDate': scheduledDate,
        'scheduledTime': scheduledTime,
        'venueName': venueName,
        'status': status,
        'chatRoomId': chatRoomId,
        'gameId': gameId,
        'confirmedAt': confirmedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'acceptances': acceptances?.map((e) => e.toJson()).toList(),
        'isCasual': isCasual,
        if (gameResult != null) 'gameResult': gameResult,
        if (pinName != null) 'pinName': pinName,
        'encounterCount': encounterCount,
        if (desiredDate != null) 'desiredDate': desiredDate,
        if (desiredTimeSlot != null) 'desiredTimeSlot': desiredTimeSlot,
        if (myScoreChange != null) 'myScoreChange': myScoreChange,
        if (myVerificationCode != null) 'myVerificationCode': myVerificationCode,
        'myResultSubmitted': myResultSubmitted,
      };

  /// 서버 응답의 acceptances 배열 또는 myAcceptance 단일 객체 모두 처리
  static List<MatchAcceptance>? _parseAcceptances(Map<String, dynamic> json) {
    // 배열로 내려오는 경우
    final list = json['acceptances'] as List<dynamic>?;
    if (list != null && list.isNotEmpty) {
      return list
          .map((e) => MatchAcceptance.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // 서버가 myAcceptance 단일 객체로 내려주는 경우
    final myAcc = json['myAcceptance'] as Map<String, dynamic>?;
    if (myAcc != null) {
      return [MatchAcceptance.fromJson(myAcc)];
    }
    return null;
  }

  bool get isPendingAccept => status == 'PENDING_ACCEPT';
  bool get isChat => status == 'CHAT';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';
  bool get isDisputed => status == 'DISPUTED';

  /// 희망 시간대 표시 텍스트
  String get desiredTimeSlotDisplayName {
    switch (desiredTimeSlot) {
      case 'DAWN': return '새벽 (0~3시)';
      case 'EARLY_MORNING': return '이른 아침 (3~6시)';
      case 'MORNING': return '오전 (6~9시)';
      case 'LATE_MORNING': return '오전 늦게 (9~12시)';
      case 'AFTERNOON': return '오후 (12~15시)';
      case 'LATE_AFTERNOON': return '오후 늦게 (15~18시)';
      case 'EVENING': return '저녁 (18~21시)';
      case 'NIGHT': return '밤 (21~24시)';
      case 'ANY': return '하루종일';
      default: return desiredTimeSlot ?? '';
    }
  }

  /// 경기 확정 가능 여부
  bool get canConfirm => isChat;

  /// 결과 입력 가능 여부
  bool get canInputResult => isConfirmed;

  String get statusDisplayName {
    switch (status) {
      case 'PENDING_ACCEPT':
        return '수락 대기';
      case 'CHAT':
        return '채팅 중';
      case 'CONFIRMED':
        return '경기 확정';
      case 'COMPLETED':
        return '완료';
      case 'CANCELLED':
        return '취소됨';
      case 'DISPUTED':
        return '분쟁 중';
      default:
        return status;
    }
  }

  String get sportTypeDisplayName => sportLabel(sportType);
}

/// 매칭 상대 정보
class MatchOpponent {
  final String id;
  final String nickname;
  final String? profileImageUrl;
  final String tier;
  // currentScore는 서버에서 비공개 처리됨 — null일 수 있음
  final int? currentScore;
  final String sportType;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final double? gHandicap;
  final String? matchMessage; // 상대방의 매칭 문구
  final bool isPlacement;             // 배치 게임 진행 중 여부
  final int? placementGamesRemaining; // 배치 게임 남은 횟수
  /// 유저에게 표시되는 점수. null이면 currentScore로 폴백.
  final int? displayScore;

  const MatchOpponent({
    required this.id,
    required this.nickname,
    this.profileImageUrl,
    required this.tier,
    this.currentScore, // 비공개 정책으로 서버에서 전달하지 않음
    required this.sportType,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    this.gHandicap,
    this.matchMessage,
    this.isPlacement = false,
    this.placementGamesRemaining,
    this.displayScore,
  });

  factory MatchOpponent.fromJson(Map<String, dynamic> json) {
    return MatchOpponent(
      id: json['id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      profileImageUrl: json['profileImageUrl'] as String?,
      tier: json['tier'] as String? ?? 'IRON',
      currentScore: json['currentScore'] as int?, // 비공개 시 null
      displayScore: json['displayScore'] as int? ?? json['currentScore'] as int?,
      sportType: json['sportType'] as String? ?? 'GOLF',
      gamesPlayed: json['gamesPlayed'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      gHandicap: json['gHandicap'] != null
          ? (json['gHandicap'] as num).toDouble()
          : null,
      matchMessage: json['matchMessage'] as String?,
      isPlacement: json['isPlacement'] as bool? ?? false,
      placementGamesRemaining: json['placementGamesRemaining'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'profileImageUrl': profileImageUrl,
        'tier': tier,
        if (currentScore != null) 'currentScore': currentScore,
        if (displayScore != null) 'displayScore': displayScore,
        'sportType': sportType,
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'losses': losses,
        'gHandicap': gHandicap,
        'matchMessage': matchMessage,
        'isPlacement': isPlacement,
        if (placementGamesRemaining != null) 'placementGamesRemaining': placementGamesRemaining,
      };
}

/// 매칭 수락/거절 정보
class MatchAcceptance {
  final String userId;
  final bool? accepted;
  final DateTime? respondedAt;
  final DateTime? expiresAt;

  const MatchAcceptance({
    required this.userId,
    this.accepted,
    this.respondedAt,
    this.expiresAt,
  });

  factory MatchAcceptance.fromJson(Map<String, dynamic> json) {
    return MatchAcceptance(
      userId: json['userId'] as String? ?? '',
      accepted: json['accepted'] as bool?,
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'accepted': accepted,
        'respondedAt': respondedAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };
}
