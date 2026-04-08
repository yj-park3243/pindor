import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/sports_profile.dart';

class ProfileRepository {
  final ApiClient _api;

  const ProfileRepository(this._api);

  Future<SportsProfile> createSportsProfile({
    required String sportType,
    String? displayName,
    String? matchMessage,
    double? gHandicap,
  }) async {
    final response = await _api.post(
      '/sports-profiles',
      body: {
        'sportType': sportType,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (matchMessage != null && matchMessage.isNotEmpty) 'matchMessage': matchMessage,
        if (gHandicap != null) 'gHandicap': gHandicap,
      },
    );
    return SportsProfile.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<SportsProfile> updateSportsProfile(
    String profileId, {
    String? displayName,
    String? matchMessage,
    double? gHandicap,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (matchMessage != null) body['matchMessage'] = matchMessage;
    if (gHandicap != null) body['gHandicap'] = gHandicap;

    final response = await _api.patch('/sports-profiles/$profileId', body: body);
    return SportsProfile.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<SportsProfile>> getMySportsProfiles() async {
    final response = await _api.get('/sports-profiles');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => SportsProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 스포츠 프로필 삭제
  /// NOTE: 서버에 DELETE /sports-profiles/:id 라우트가 없음 — 서버 추가 필요
  Future<void> deleteSportsProfile(String profileId) async {
    await _api.delete('/sports-profiles/$profileId');
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ApiClient.instance);
});
