import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/notice.dart';

class NoticeRepository {
  final ApiClient _api;

  const NoticeRepository(this._api);

  Future<List<Notice>> getNotices({int page = 1, int limit = 20}) async {
    final response = await _api.get(
      '/notices',
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Notice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Notice>> getPinnedNotices() async {
    final response = await _api.get('/notices/pinned');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Notice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Notice> getNotice(String id) async {
    final response = await _api.get('/notices/$id');
    return Notice.fromJson(response['data'] as Map<String, dynamic>);
  }
}

final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  return NoticeRepository(ApiClient.instance);
});
