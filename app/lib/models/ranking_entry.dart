/// 랭킹 항목 모델
class RankingEntry {
  final String id;
  final String pinId;
  final String sportsProfileId;
  final String userId;
  final String nickname;
  final String? profileImageUrl;
  final String sportType;
  final int rank;
  final int score;
  final String tier;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final double? gHandicap;
  final DateTime updatedAt;

  const RankingEntry({
    required this.id,
    required this.pinId,
    required this.sportsProfileId,
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
    required this.sportType,
    required this.rank,
    required this.score,
    required this.tier,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    this.gHandicap,
    required this.updatedAt,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) {
    final profile = json['sportsProfile'] as Map<String, dynamic>?;
    return RankingEntry(
      id: json['id'] as String? ?? '',
      pinId: json['pinId'] as String? ?? '',
      sportsProfileId:
          profile?['id'] as String? ?? json['sportsProfileId'] as String? ?? '',
      userId: profile?['userId'] as String? ?? json['userId'] as String? ?? '',
      nickname: profile?['nickname'] as String? ??
          json['nickname'] as String? ?? '',
      profileImageUrl: profile?['profileImageUrl'] as String? ??
          json['profileImageUrl'] as String?,
      sportType: json['sportType'] as String? ?? 'GOLF',
      rank: json['rank'] as int? ?? 0,
      score: profile?['score'] as int? ??
          profile?['currentScore'] as int? ??
          json['score'] as int? ?? 0,
      tier: profile?['tier'] as String? ?? json['tier'] as String? ?? 'BRONZE',
      gamesPlayed:
          profile?['gamesPlayed'] as int? ?? json['gamesPlayed'] as int? ?? 0,
      wins: profile?['wins'] as int? ?? json['wins'] as int? ?? 0,
      losses: profile?['losses'] as int? ?? json['losses'] as int? ?? 0,
      gHandicap: profile?['gHandicap'] != null
          ? (profile!['gHandicap'] as num).toDouble()
          : json['gHandicap'] != null
              ? (json['gHandicap'] as num).toDouble()
              : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  bool get isTop3 => rank <= 3;
}

/// 핀 랭킹 응답 (핀 정보 + 랭킹 목록 + 내 랭킹)
class PinRankingData {
  final PinInfo pin;
  final List<RankingEntry> rankings;
  final MyRankInfo? myRank;

  const PinRankingData({
    required this.pin,
    required this.rankings,
    this.myRank,
  });

  factory PinRankingData.fromJson(Map<String, dynamic> json) {
    return PinRankingData(
      pin: PinInfo.fromJson(json['pin'] as Map<String, dynamic>),
      rankings: (json['rankings'] as List<dynamic>?)
              ?.map((e) =>
                  RankingEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      myRank: json['myRank'] != null
          ? MyRankInfo.fromJson(json['myRank'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PinInfo {
  final String id;
  final String name;
  final String level;

  const PinInfo({required this.id, required this.name, required this.level});

  factory PinInfo.fromJson(Map<String, dynamic> json) {
    return PinInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      level: json['level'] as String? ?? 'DONG',
    );
  }
}

class MyRankInfo {
  final int rank;
  final int score;
  final String tier;
  final String? userId;

  const MyRankInfo({required this.rank, required this.score, this.tier = 'BRONZE', this.userId});

  factory MyRankInfo.fromJson(Map<String, dynamic> json) {
    return MyRankInfo(
      rank: json['rank'] as int,
      score: json['score'] as int,
      tier: json['tier'] as String? ?? 'BRONZE',
      userId: json['userId'] as String?,
    );
  }
}
