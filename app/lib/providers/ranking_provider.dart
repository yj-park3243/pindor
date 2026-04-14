import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ranking_entry.dart';
import '../repositories/ranking_repository.dart';

/// 핀 랭킹 프로바이더 (pinId 단독 — 기본 종목 GOLF)
final pinRankingProvider =
    FutureProvider.autoDispose.family<PinRankingData, String>(
  (ref, pinId) async {
    final repo = ref.read(rankingRepositoryProvider);
    return repo.getPinRanking(pinId);
  },
);

/// 핀 랭킹 프로바이더 (pinId + sportType)
final pinRankingBySportProvider =
    FutureProvider.autoDispose.family<PinRankingData, ({String pinId, String sportType})>(
  (ref, params) async {
    final repo = ref.read(rankingRepositoryProvider);
    return repo.getPinRanking(params.pinId, sportType: params.sportType);
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

/// 종목별 자주가는 핀 등수 프로바이더
final myPinRankProvider =
    FutureProvider.autoDispose.family<int?, String>((ref, sportType) async {
  final repo = ref.read(rankingRepositoryProvider);
  return repo.getMyPrimaryPinRank(sportType);
});

/// 종목별 최고 점수 핀 정보 프로바이더
final myBestPinScoreProvider =
    FutureProvider.autoDispose.family<BestPinScore?, String>((ref, sportType) async {
  final repo = ref.read(rankingRepositoryProvider);
  return repo.getMyBestPinScore(sportType);
});

/// 내가 경기한 핀 ID 집합 프로바이더
final myParticipatedPinIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  ref.keepAlive();
  final repo = ref.read(rankingRepositoryProvider);
  return repo.getMyParticipatedPinIds();
});

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
