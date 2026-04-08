import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

/// 신고/문의 Repository
class SupportRepository {
  final ApiClient _api;

  const SupportRepository(this._api);

  /// 신고 접수
  /// [targetType]: USER | POST | COMMENT | CHAT | MATCH
  /// [targetId]: 신고 대상 ID
  /// [reason]: MANNER | ABUSIVE | NOSHOW | SPAM | OTHER
  /// [description]: 선택 입력 상세 내용
  Future<void> createReport({
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    await _api.post('/reports', body: {
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      if (description != null && description.isNotEmpty)
        'description': description,
    });
  }

  /// 문의 접수
  /// [category]: ACCOUNT | MATCH | SCORE | BUG | SUGGESTION | OTHER
  /// [title]: 문의 제목
  /// [content]: 문의 내용
  Future<void> createInquiry({
    required String category,
    required String title,
    required String content,
  }) async {
    await _api.post('/inquiries', body: {
      'category': category,
      'title': title,
      'content': content,
    });
  }

  /// 내 문의 목록 조회
  Future<List<Map<String, dynamic>>> getMyInquiries() async {
    final response = await _api.get('/inquiries');
    final data = response['data'] as List<dynamic>? ?? [];
    return data.cast<Map<String, dynamic>>();
  }
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ApiClient.instance);
});
