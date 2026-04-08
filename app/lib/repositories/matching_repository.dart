import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/local/daos/matches_dao.dart';
import '../data/local/cache_ttl_helper.dart';
import '../data/local/database_provider.dart';
import '../models/match_request.dart';
import '../models/match.dart';

class MatchingRepository {
  final ApiClient _api;
  final MatchesDao _dao;
  final CacheTtlHelper _cache;

  static const _cacheKey = 'matches';

  const MatchingRepository(this._api, this._dao, this._cache);

  /// 매칭 요청 생성
  Future<MatchRequest> createMatchRequest(
      Map<String, dynamic> data) async {
    // genderPreference, minAge, maxAge가 포함된 body를 그대로 전달
    final response = await _api.post('/matches/requests', body: data);
    return MatchRequest.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 즉시 매칭 ("오늘 대결")
  Future<MatchRequest> createInstantMatch(Map<String, dynamic> data) async {
    final response = await _api.post('/matches/instant', body: data);
    return MatchRequest.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 내 매칭 요청 목록
  Future<List<MatchRequest>> getMyMatchRequests({String? type}) async {
    final response = await _api.get(
      '/matches/requests',
      queryParameters: type != null ? {'type': type} : null,
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => MatchRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 매칭 요청 취소
  Future<void> cancelMatchRequest(String requestId) async {
    await _api.delete('/matches/requests/$requestId');
  }

  /// 내 매칭 목록 (API → 로컬 DB 저장)
  Future<List<Match>> getMyMatches({
    String? status,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _api.get(
      '/matches',
      queryParameters: {
        if (status != null) 'status': status,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final data = response['data'] as List<dynamic>;
    final matches = data.map((e) => Match.fromJson(e as Map<String, dynamic>)).toList();
    await _dao.upsertMatches(matches);
    await _cache.update(_cacheKey);
    return matches;
  }

  /// 로컬 매칭 목록
  Future<List<Match>> getMyMatchesLocal({String? status}) {
    return _dao.getMatches(status: status);
  }

  /// 로컬 매칭 캐시 유무
  Future<bool> hasMatchesCache() async {
    final count = await _dao.getMatchCount();
    return count > 0;
  }

  /// TTL 만료 시만 API 호출
  Future<void> refreshIfStale() async {
    final expired = await _cache.isExpired(_cacheKey, CacheTtlHelper.matchesTtl);
    if (!expired) return;
    try {
      await getMyMatches();
    } catch (e) {
      debugPrint('[MatchRepo] 매칭 갱신 실패: $e');
    }
  }

  /// 매칭 상세 (API → 로컬 DB 저장)
  Future<Match> getMatchDetail(String matchId) async {
    final response = await _api.get('/matches/$matchId');
    final match = Match.fromJson(response['data'] as Map<String, dynamic>);
    await _dao.upsertMatch(match);
    return match;
  }

  /// 로컬 매칭 상세
  Future<Match?> getMatchDetailLocal(String matchId) {
    return _dao.getMatch(matchId);
  }

  /// 경기 확정
  Future<Match> confirmMatch(
    String matchId, {
    required String scheduledDate,
    required String scheduledTime,
    required String venueName,
    double? venueLatitude,
    double? venueLongitude,
  }) async {
    final response = await _api.patch(
      '/matches/$matchId/confirm',
      body: {
        'scheduledDate': scheduledDate,
        'scheduledTime': scheduledTime,
        'venueName': venueName,
        if (venueLatitude != null) 'venueLatitude': venueLatitude,
        if (venueLongitude != null) 'venueLongitude': venueLongitude,
      },
    );
    final match = Match.fromJson(response['data'] as Map<String, dynamic>);
    await _dao.upsertMatch(match);
    return match;
  }

  /// 경기 취소
  Future<void> cancelMatch(String matchId, {String? reason}) async {
    await _api.patch(
      '/matches/$matchId/cancel',
      body: {'reason': reason ?? '사용자 취소'},
    );
  }

  /// 매칭 수락
  Future<Match> acceptMatch(String matchId) async {
    final response = await _api.post('/matches/$matchId/accept');
    final match = Match.fromJson(response['data'] as Map<String, dynamic>);
    await _dao.upsertMatch(match);
    return match;
  }

  /// 매칭 거절
  Future<void> rejectMatch(String matchId) async {
    await _api.post('/matches/$matchId/reject');
  }

  /// 매칭 상태 조회 (폴링용)
  Future<Match> getMatchStatus(String matchId) async {
    final response = await _api.get('/matches/$matchId/status');
    return Match.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 활성 매칭 조회 — PENDING_ACCEPT / CHAT / CONFIRMED 상태 매칭
  /// 앱 시작 시 또는 소켓 재연결 시 화면 잠금 여부 판단에 사용
  Future<Match?> getActiveMatch() async {
    try {
      final response = await _api.get('/matches/active');
      final data = response['data'];
      if (data == null) return null;
      return Match.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 매칭 포기 — 패배 처리 및 점수 하락
  Future<void> forfeitMatch(String matchId) async {
    await _api.post('/matches/$matchId/forfeit');
  }

  /// 노쇼 신고 — 상대방이 약속 장소에 나타나지 않은 경우
  Future<void> reportNoshow(String matchId) async {
    await _api.post('/matches/$matchId/report-noshow');
  }
}

final matchingRepositoryProvider = Provider<MatchingRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final cache = ref.watch(cacheTtlHelperProvider);
  return MatchingRepository(ApiClient.instance, MatchesDao(db), cache);
});
