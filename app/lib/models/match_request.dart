/// 매칭 요청 모델
class MatchRequest {
  final String id;
  final String requesterId;
  final String requesterNickname;
  final String? requesterProfileImageUrl;
  final String requesterTier;
  final int requesterScore;
  final String sportType;
  final String requestType; // SCHEDULED | INSTANT
  final String? desiredDate; // YYYY-MM-DD
  final String desiredTimeSlot; // MORNING | AFTERNOON | EVENING | ANY
  final double latitude;
  final double longitude;
  final String? locationName;
  final String? pinName;
  final double radiusKm;
  final int minOpponentScore;
  final int maxOpponentScore;
  final String? message;
  final String status; // WAITING | MATCHED | CANCELLED | EXPIRED
  final int candidatesCount;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String genderPreference; // ANY | SAME | MALE | FEMALE
  final bool isCasual;
  final int? minAge;
  final int? maxAge;

  const MatchRequest({
    required this.id,
    required this.requesterId,
    required this.requesterNickname,
    this.requesterProfileImageUrl,
    required this.requesterTier,
    required this.requesterScore,
    required this.sportType,
    required this.requestType,
    this.desiredDate,
    required this.desiredTimeSlot,
    required this.latitude,
    required this.longitude,
    this.locationName,
    this.pinName,
    required this.radiusKm,
    required this.minOpponentScore,
    required this.maxOpponentScore,
    this.message,
    required this.status,
    required this.candidatesCount,
    required this.expiresAt,
    required this.createdAt,
    this.genderPreference = 'ANY',
    this.isCasual = false,
    this.minAge,
    this.maxAge,
  });

  factory MatchRequest.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'] as Map<String, dynamic>?;
    return MatchRequest(
      id: json['id'] as String,
      requesterId: json['requesterId'] as String? ??
          (requester?['id'] as String? ?? ''),
      requesterNickname: requester?['nickname'] as String? ?? '',
      requesterProfileImageUrl:
          requester?['profileImageUrl'] as String?,
      requesterTier: requester?['tier'] as String? ?? 'BRONZE',
      requesterScore: requester?['currentScore'] as int? ?? 1000,
      sportType: json['sportType'] as String? ?? 'GOLF',
      requestType: json['requestType'] as String? ?? 'SCHEDULED',
      desiredDate: json['desiredDate'] as String?,
      desiredTimeSlot: json['desiredTimeSlot'] as String? ?? 'ANY',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      locationName: json['locationName'] as String?,
      pinName: json['pinName'] as String?,
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? 10.0,
      minOpponentScore: json['minOpponentScore'] as int? ?? 800,
      maxOpponentScore: json['maxOpponentScore'] as int? ?? 1600,
      message: json['message'] as String?,
      status: json['status'] as String? ?? 'WAITING',
      candidatesCount: json['candidatesCount'] as int? ?? 0,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : DateTime.now().add(const Duration(hours: 24)),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      genderPreference: json['genderPreference'] as String? ?? 'ANY',
      isCasual: json['isCasual'] as bool? ?? false,
      minAge: json['minAge'] as int?,
      maxAge: json['maxAge'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'requesterId': requesterId,
        'sportType': sportType,
        'requestType': requestType,
        'desiredDate': desiredDate,
        'desiredTimeSlot': desiredTimeSlot,
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'radiusKm': radiusKm,
        'minOpponentScore': minOpponentScore,
        'maxOpponentScore': maxOpponentScore,
        'message': message,
        'status': status,
        'candidatesCount': candidatesCount,
        'expiresAt': expiresAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'genderPreference': genderPreference,
        'isCasual': isCasual,
        'minAge': minAge,
        'maxAge': maxAge,
      };

  bool get isWaiting => status == 'WAITING';
  bool get isMatched => status == 'MATCHED';
  bool get isCancelled => status == 'CANCELLED';
  bool get isExpired => status == 'EXPIRED';

  String get timeSlotDisplayName {
    switch (desiredTimeSlot) {
      case 'DAWN':
        return '새벽 (0~3시)';
      case 'EARLY_MORNING':
        return '이른 아침 (3~6시)';
      case 'MORNING':
        return '오전 (6~9시)';
      case 'LATE_MORNING':
        return '오전 늦게 (9~12시)';
      case 'AFTERNOON':
        return '오후 (12~15시)';
      case 'LATE_AFTERNOON':
        return '오후 늦게 (15~18시)';
      case 'EVENING':
        return '저녁 (18~21시)';
      case 'NIGHT':
        return '밤 (21~24시)';
      case 'ANY':
        return '아무 때나';
      default:
        return desiredTimeSlot;
    }
  }

  bool get isInstant => requestType == 'INSTANT';
}
