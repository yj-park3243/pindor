import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/ranking_entry.dart';
import '../models/pin.dart';
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

  Future<List<Pin>> getNearbyPins({
    required double latitude,
    required double longitude,
    String sportType = 'GOLF',
  }) async {
    // 주변 핀 목록은 /pins/nearby 엔드포인트 사용
    final response = await _api.get(
      '/pins/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radius': 10,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data.map((e) => Pin.fromJson(e as Map<String, dynamic>)).toList();
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
