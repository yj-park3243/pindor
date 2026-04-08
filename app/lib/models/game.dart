/// 경기 모델
class Game {
  final String id;
  final String matchId;
  final String sportType;
  final String? venueName;
  final double? venueLatitude;
  final double? venueLongitude;
  final DateTime? playedAt;
  final String resultStatus; // PENDING | PROOF_UPLOADED | VERIFIED | DISPUTED | VOIDED
  final String? winnerId;
  final String? requesterProfileId;
  final String? opponentProfileId;
  final String? requesterUserId;
  final String? opponentUserId;
  final GameResult? myResult;
  final GameResult? opponentResult;
  final List<ResultProof> proofs;
  final DateTime createdAt;

  const Game({
    required this.id,
    required this.matchId,
    required this.sportType,
    this.venueName,
    this.venueLatitude,
    this.venueLongitude,
    this.playedAt,
    required this.resultStatus,
    this.winnerId,
    this.requesterProfileId,
    this.opponentProfileId,
    this.requesterUserId,
    this.opponentUserId,
    this.myResult,
    this.opponentResult,
    this.proofs = const [],
    required this.createdAt,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    final matchData = json['match'] as Map<String, dynamic>?;
    final requesterProfile =
        matchData?['requesterProfile'] as Map<String, dynamic>?;
    final opponentProfile =
        matchData?['opponentProfile'] as Map<String, dynamic>?;

    return Game(
      id: json['id'] as String,
      matchId: json['matchId'] as String? ?? '',
      sportType: json['sportType'] as String? ?? 'GOLF',
      venueName: json['venueName'] as String?,
      venueLatitude: json['venueLatitude'] != null
          ? (json['venueLatitude'] as num).toDouble()
          : null,
      venueLongitude: json['venueLongitude'] != null
          ? (json['venueLongitude'] as num).toDouble()
          : null,
      playedAt: json['playedAt'] != null
          ? DateTime.parse(json['playedAt'] as String)
          : null,
      resultStatus: json['resultStatus'] as String? ?? 'PENDING',
      winnerId: json['winnerId'] as String?,
      requesterProfileId: requesterProfile?['id'] as String?,
      opponentProfileId: opponentProfile?['id'] as String?,
      requesterUserId:
          (requesterProfile?['user'] as Map<String, dynamic>?)?['id']
              as String? ??
          requesterProfile?['userId'] as String?,
      opponentUserId:
          (opponentProfile?['user'] as Map<String, dynamic>?)?['id']
              as String? ??
          opponentProfile?['userId'] as String?,
      myResult: json['myResult'] != null
          ? GameResult.fromJson(json['myResult'] as Map<String, dynamic>)
          : null,
      opponentResult: json['opponentResult'] != null
          ? GameResult.fromJson(
              json['opponentResult'] as Map<String, dynamic>)
          : null,
      proofs: (json['proofs'] as List<dynamic>?)
              ?.map((e) => ResultProof.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  bool get isPending => resultStatus == 'PENDING';
  bool get isProofUploaded => resultStatus == 'PROOF_UPLOADED';
  bool get isVerified => resultStatus == 'VERIFIED';
  bool get isDisputed => resultStatus == 'DISPUTED';
  bool get isVoided => resultStatus == 'VOIDED';
}

/// 경기 결과 입력
class GameResult {
  final String id;
  final String gameId;
  final String sportsProfileId;
  final int myScore;
  final int opponentScore;
  final String winnerId;
  final bool isConfirmed;
  final String? comment;
  final DateTime submittedAt;

  const GameResult({
    required this.id,
    required this.gameId,
    required this.sportsProfileId,
    required this.myScore,
    required this.opponentScore,
    required this.winnerId,
    required this.isConfirmed,
    this.comment,
    required this.submittedAt,
  });

  factory GameResult.fromJson(Map<String, dynamic> json) {
    return GameResult(
      id: json['id'] as String,
      gameId: json['gameId'] as String? ?? '',
      sportsProfileId: json['sportsProfileId'] as String? ?? '',
      myScore: json['myScore'] as int? ?? 0,
      opponentScore: json['opponentScore'] as int? ?? 0,
      winnerId: json['winnerId'] as String? ?? '',
      isConfirmed: json['isConfirmed'] as bool? ?? false,
      comment: json['comment'] as String?,
      submittedAt: json['submittedAt'] != null
          ? DateTime.parse(json['submittedAt'] as String)
          : DateTime.now(),
    );
  }
}

/// 경기 결과 증빙 사진
class ResultProof {
  final String id;
  final String imageUrl;
  final String imageType; // SCORECARD | OTHER

  const ResultProof({
    required this.id,
    required this.imageUrl,
    required this.imageType,
  });

  factory ResultProof.fromJson(Map<String, dynamic> json) {
    return ResultProof(
      id: json['id'] as String,
      imageUrl: json['imageUrl'] as String,
      imageType: json['imageType'] as String? ?? 'SCORECARD',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageUrl': imageUrl,
        'imageType': imageType,
      };
}

/// 점수 변동 결과 (결과 화면용)
class ScoreChangeResult {
  final int previousScore;
  final int newScore;
  final int scoreDelta;
  final String previousTier;
  final String newTier;
  final bool tierChanged;
  final bool tierUpgraded;
  final int? previousRank;
  final int? newRank;
  final bool isWin;

  const ScoreChangeResult({
    required this.previousScore,
    required this.newScore,
    required this.scoreDelta,
    required this.previousTier,
    required this.newTier,
    required this.tierChanged,
    required this.tierUpgraded,
    this.previousRank,
    this.newRank,
    required this.isWin,
  });

  factory ScoreChangeResult.fromJson(Map<String, dynamic> json) {
    return ScoreChangeResult(
      previousScore: json['previousScore'] as int,
      newScore: json['newScore'] as int,
      scoreDelta: json['scoreDelta'] as int,
      previousTier: json['previousTier'] as String,
      newTier: json['newTier'] as String,
      tierChanged: json['tierChanged'] as bool? ?? false,
      tierUpgraded: json['tierUpgraded'] as bool? ?? false,
      previousRank: json['previousRank'] as int?,
      newRank: json['newRank'] as int?,
      isWin: json['isWin'] as bool? ?? false,
    );
  }
}
