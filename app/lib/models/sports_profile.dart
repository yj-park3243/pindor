/// 스포츠 프로필 모델
/// 종목별 점수, 티어, G핸디(골프 전용) 관리
class SportsProfile {
  final String id;
  final String userId;
  final String sportType; // GOLF | BILLIARDS | TENNIS | TABLE_TENNIS
  final String displayName;
  final String? matchMessage; // 매칭 시 상대에게 보이는 한줄 소개
  final int initialScore;
  final int currentScore;
  final String tier; // IRON | BRONZE | SILVER | GOLD | PLATINUM | MASTER | GRANDMASTER
  final double? gHandicap; // 골프 전용 G핸디
  final bool isVerified;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final bool isActive;
  final DateTime createdAt;

  // ─── 승급 프로그레스 필드 (서버 미지원 시 null) ───
  final int? pointsToNext;    // 다음 등급까지 필요한 점수
  final double? progress;     // 현재 등급 내 진행률 0.0 ~ 1.0
  final int? subTier;         // 서브 티어 1, 2, 3
  final String? nextTierName; // 다음 등급 이름 (예: '실버')

  // ─── displayScore / MMR 분리 ───
  /// 유저에게 표시되는 점수. 서버에서 round(glickoRating) + 보너스로 계산.
  /// null이면 currentScore로 폴백.
  final int? displayScore;

  // ─── 배치 게임 필드 ───
  final bool isPlacement;               // 배치 게임 진행 중 여부
  final int? placementGamesRemaining;   // 배치 게임 남은 횟수 (5 - gamesPlayed)
  final double? glickoRd;               // Glicko-2 RD (불확실도, 배치 중 높음)

  // ─── 매너 점수 ───
  /// 상대방들이 평가한 평균 매너 점수 (1.0 ~ 5.0). 평가 없으면 null.
  final double? mannerScore;

  const SportsProfile({
    required this.id,
    required this.userId,
    required this.sportType,
    required this.displayName,
    this.matchMessage,
    required this.initialScore,
    required this.currentScore,
    required this.tier,
    this.gHandicap,
    this.isVerified = false,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    this.isActive = true,
    required this.createdAt,
    this.pointsToNext,
    this.progress,
    this.subTier,
    this.nextTierName,
    this.displayScore,
    this.isPlacement = false,
    this.placementGamesRemaining,
    this.glickoRd,
    this.mannerScore,
  });

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  factory SportsProfile.fromJson(Map<String, dynamic> json) {
    return SportsProfile(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      sportType: json['sportType'] as String? ?? 'GOLF',
      displayName: json['displayName'] as String? ?? '',
      matchMessage: json['matchMessage'] as String?,
      initialScore: _toInt(json['initialScore']) ?? 1000,
      currentScore: _toInt(json['currentScore']) ?? 1000,
      tier: json['tier'] as String? ?? 'BRONZE',
      gHandicap: json['gHandicap'] != null
          ? double.tryParse(json['gHandicap'].toString())
          : null,
      isVerified: json['isVerified'] as bool? ?? false,
      gamesPlayed: _toInt(json['gamesPlayed']) ?? 0,
      wins: _toInt(json['wins']) ?? 0,
      losses: _toInt(json['losses']) ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      // 승급 프로그레스 — 서버 미지원 시 null로 안전 처리
      pointsToNext: json['pointsToNext'] as int?,
      progress: json['progress'] != null
          ? double.tryParse(json['progress'].toString())
          : null,
      subTier: _toInt(json['subTier']),
      nextTierName: json['nextTierName'] as String?,
      // displayScore — 없으면 currentScore 폴백
      displayScore: _toInt(json['displayScore']) ?? _toInt(json['currentScore']) ?? 1000,
      // 배치 게임 — 서버 미지원 시 false/null로 안전 처리
      isPlacement: json['isPlacement'] as bool? ?? false,
      placementGamesRemaining: _toInt(json['placementGamesRemaining']),
      glickoRd: json['glickoRd'] != null
          ? double.tryParse(json['glickoRd'].toString())
          : null,
      // 매너 점수 — 서버 미지원 시 null로 안전 처리
      mannerScore: json['mannerScore'] != null
          ? double.tryParse(json['mannerScore'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'sportType': sportType,
        'displayName': displayName,
        'matchMessage': matchMessage,
        'initialScore': initialScore,
        'currentScore': currentScore,
        'tier': tier,
        'gHandicap': gHandicap,
        'isVerified': isVerified,
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'losses': losses,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        if (pointsToNext != null) 'pointsToNext': pointsToNext,
        if (progress != null) 'progress': progress,
        if (subTier != null) 'subTier': subTier,
        if (nextTierName != null) 'nextTierName': nextTierName,
        'isPlacement': isPlacement,
        if (placementGamesRemaining != null) 'placementGamesRemaining': placementGamesRemaining,
        if (displayScore != null) 'displayScore': displayScore,
        if (glickoRd != null) 'glickoRd': glickoRd,
        if (mannerScore != null) 'mannerScore': mannerScore,
      };

  SportsProfile copyWith({
    String? displayName,
    String? matchMessage,
    int? currentScore,
    int? displayScore,
    String? tier,
    double? gHandicap,
    bool? isVerified,
    int? gamesPlayed,
    int? wins,
    int? losses,
    bool? isActive,
    int? pointsToNext,
    double? progress,
    int? subTier,
    String? nextTierName,
    bool? isPlacement,
    int? placementGamesRemaining,
    double? glickoRd,
    double? mannerScore,
  }) {
    return SportsProfile(
      id: id,
      userId: userId,
      sportType: sportType,
      displayName: displayName ?? this.displayName,
      matchMessage: matchMessage ?? this.matchMessage,
      initialScore: initialScore,
      currentScore: currentScore ?? this.currentScore,
      displayScore: displayScore ?? this.displayScore,
      tier: tier ?? this.tier,
      gHandicap: gHandicap ?? this.gHandicap,
      isVerified: isVerified ?? this.isVerified,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      pointsToNext: pointsToNext ?? this.pointsToNext,
      progress: progress ?? this.progress,
      subTier: subTier ?? this.subTier,
      nextTierName: nextTierName ?? this.nextTierName,
      isPlacement: isPlacement ?? this.isPlacement,
      placementGamesRemaining: placementGamesRemaining ?? this.placementGamesRemaining,
      glickoRd: glickoRd ?? this.glickoRd,
      mannerScore: mannerScore ?? this.mannerScore,
    );
  }

  double get winRate => gamesPlayed > 0 ? (wins / gamesPlayed * 100) : 0.0;

  String get sportTypeDisplayName {
    switch (sportType) {
      case 'GOLF':
        return '골프';
      case 'BILLIARDS':
        return '당구';
      case 'TENNIS':
        return '테니스';
      case 'TABLE_TENNIS':
        return '탁구';
      default:
        return sportType;
    }
  }

  String get tierDisplayName {
    switch (tier) {
      case 'BRONZE':
        return '브론즈';
      case 'SILVER':
        return '실버';
      case 'GOLD':
        return '골드';
      case 'PLATINUM':
        return '플래티넘';
      default:
        return tier;
    }
  }

  /// G핸디로 초기 점수 계산
  /// 변동폭을 작게 유지 (950~1050) — 배치 게임에서 실력 반영
  static int calculateInitialScore(double gHandicap) {
    // 0~54 핸디를 1050~950 범위로 선형 매핑
    final score = 1050 - (gHandicap / 54 * 100).round();
    return score.clamp(950, 1050);
  }
}
