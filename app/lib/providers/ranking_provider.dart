import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ranking_entry.dart';
import '../models/pin.dart';
import '../repositories/ranking_repository.dart';

/// 현재 위치 기반 핀 목록
final nearbyPinsProvider = FutureProvider.autoDispose
    .family<List<Pin>, ({double lat, double lng})>(
  (ref, coords) async {
    final repo = ref.read(rankingRepositoryProvider);
    return repo.getNearbyPins(
        latitude: coords.lat, longitude: coords.lng);
  },
);

/// 핀 랭킹 프로바이더
final pinRankingProvider =
    FutureProvider.autoDispose.family<PinRankingData, String>(
  (ref, pinId) async {
    final repo = ref.read(rankingRepositoryProvider);
    return repo.getPinRanking(pinId);
  },
);

/// 전국 랭킹 프로바이더
final nationalRankingProvider =
    FutureProvider.autoDispose.family<List<RankingEntry>, String>(
  (ref, sportType) async {
    final repo = ref.read(rankingRepositoryProvider);
    return repo.getNationalRanking(sportType: sportType);
  },
);

/// 내 랭킹 히스토리 프로바이더 (profileId 필요)
final myRankingHistoryProvider =
    FutureProvider.autoDispose.family<List<ScoreHistory>, String>((ref, profileId) async {
  final repo = ref.read(rankingRepositoryProvider);
  return repo.getMyScoreHistory(profileId);
});

/// 점수 히스토리 모델
class ScoreHistory {
  final DateTime date;
  final int score;
  final int rank;
  final String tier;
  final String? opponentNickname;
  final bool isWin;

  const ScoreHistory({
    required this.date,
    required this.score,
    required this.rank,
    required this.tier,
    this.opponentNickname,
    required this.isWin,
  });

  factory ScoreHistory.fromJson(Map<String, dynamic> json) {
    return ScoreHistory(
      date: DateTime.parse(json['date'] as String),
      score: json['score'] as int,
      rank: json['rank'] as int? ?? 0,
      tier: json['tier'] as String? ?? 'BRONZE',
      opponentNickname: json['opponentNickname'] as String?,
      isWin: json['isWin'] as bool? ?? false,
    );
  }
}
