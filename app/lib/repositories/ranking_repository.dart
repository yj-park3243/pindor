import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/ranking_entry.dart';
import '../providers/ranking_provider.dart';

class RankingRepository {
  final ApiClient _api;

  const RankingRepository(this._api);

  Future<PinRankingData> getPinRanking(
    String pinId, {
    String sportType = 'GOLF',
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/rankings/pins/$pinId',
      queryParameters: {'sportType': sportType, 'limit': limit},
    );
    return PinRankingData.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<RankingEntry>> getNationalRanking({
    String sportType = 'GOLF',
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/rankings/national',
      queryParameters: {
        'sportType': sportType,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => RankingEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 종목별 자주가는 핀 등수 조회 (GET /rankings/me)
  /// 반환: 자주가는 핀(isPrimary)의 등수, 없으면 null
  Future<int?> getMyPrimaryPinRank(String sportType) async {
    try {
      final response = await _api.get(
        '/rankings/me',
        queryParameters: {'sportType': sportType},
      );
      final data = response['data'] as Map<String, dynamic>;
      final pinRankings = data['pinRankings'] as List<dynamic>;
      // isPrimary 핀의 등수 반환
      for (final e in pinRankings) {
        final entry = e as Map<String, dynamic>;
        if (entry['isPrimary'] == true && entry['rank'] != null) {
          return entry['rank'] as int;
        }
      }
      // isPrimary 없으면 첫 번째 핀의 등수
      if (pinRankings.isNotEmpty) {
        final first = pinRankings.first as Map<String, dynamic>;
        return first['rank'] as int?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 종목별 최고 점수 핀 정보 조회 (GET /rankings/me)
  /// 반환: {pinName, score, rank, tier} — 모든 핀 중 가장 높은 점수
  Future<BestPinScore?> getMyBestPinScore(String sportType) async {
    try {
      final response = await _api.get(
        '/rankings/me',
        queryParameters: {'sportType': sportType},
      );
      final data = response['data'] as Map<String, dynamic>;
      final pinRankings = data['pinRankings'] as List<dynamic>;
      if (pinRankings.isEmpty) return null;

      // score가 가장 높은 핀 찾기
      Map<String, dynamic>? best;
      for (final e in pinRankings) {
        final entry = e as Map<String, dynamic>;
        if (entry['rank'] == null) continue;
        if (best == null || (entry['score'] as int) > (best['score'] as int)) {
          best = entry;
        }
      }
      if (best == null) return null;

      final pin = best['pin'] as Map<String, dynamic>;
      return BestPinScore(
        pinName: pin['name'] as String,
        score: best['score'] as int,
        rank: best['rank'] as int,
        tier: best['tier'] as String? ?? 'IRON',
      );
    } catch (_) {
      return null;
    }
  }

  /// 내가 경기한 핀 ID 목록 조회 (GET /rankings/me)
  Future<Set<String>> getMyParticipatedPinIds({
    String sportType = 'GOLF',
  }) async {
    try {
      final response = await _api.get(
        '/rankings/me',
        queryParameters: {'sportType': sportType},
      );
      final data = response['data'] as Map<String, dynamic>;
      final pinRankings = data['pinRankings'] as List<dynamic>;
      return pinRankings
          .where((e) => (e as Map<String, dynamic>)['rank'] != null)
          .map((e) => (e as Map<String, dynamic>)['pin']['id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// 내 점수 히스토리 조회
  /// 서버는 /sports-profiles/:profileId/score-history 를 사용
  Future<List<ScoreHistory>> getMyScoreHistory(String profileId) async {
    final response = await _api.get('/sports-profiles/$profileId/score-history');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => ScoreHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final rankingRepositoryProvider = Provider<RankingRepository>((ref) {
  return RankingRepository(ApiClient.instance);
});

/// 종목별 최고 점수 핀 정보
class BestPinScore {
  final String pinName;
  final int score;
  final int rank;
  final String tier;

  const BestPinScore({
    required this.pinName,
    required this.score,
    required this.rank,
    required this.tier,
  });
}
