import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

/// 의의 제기 Repository
class DisputeRepository {
  final ApiClient _api;

  const DisputeRepository(this._api);

  /// 의의 제기 접수
  Future<void> createDispute({
    required String matchId,
    required String title,
    required String content,
    List<String> imageUrls = const [],
    String? phoneNumber,
  }) async {
    await _api.post('/disputes', body: {
      'matchId': matchId,
      'title': title,
      'content': content,
      if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
      if (phoneNumber != null && phoneNumber.isNotEmpty)
        'phoneNumber': phoneNumber,
    });
  }

  /// 내 의의 제기 목록 조회
  Future<List<Map<String, dynamic>>> getMyDisputes() async {
    final response = await _api.get('/disputes');
    final data = response['data'] as List<dynamic>? ?? [];
    return data.cast<Map<String, dynamic>>();
  }

  /// 의의 제기 상세 조회
  Future<Map<String, dynamic>> getDispute(String id) async {
    final response = await _api.get('/disputes/$id');
    return response['data'] as Map<String, dynamic>;
  }
}

final disputeRepositoryProvider = Provider<DisputeRepository>((ref) {
  return DisputeRepository(ApiClient.instance);
});
