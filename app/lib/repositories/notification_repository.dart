import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/notification.dart';

class NotificationRepository {
  final ApiClient _api;

  const NotificationRepository(this._api);

  Future<Map<String, dynamic>> getNotifications({
    bool? isRead,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _api.get(
      '/notifications',
      queryParameters: {
        if (isRead != null) 'isRead': isRead,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    return response as Map<String, dynamic>;
  }

  Future<void> markAsRead(String notificationId) async {
    await _api.patch('/notifications/$notificationId/read');
  }

  Future<void> markAllAsRead() async {
    await _api.patch('/notifications/read-all');
  }

  /// 알림 설정 조회
  /// NOTE: 서버에 GET /notifications/settings 라우트가 없음 — 서버 추가 필요
  /// 현재는 PATCH만 존재
  Future<NotificationSettings> getSettings() async {
    final response = await _api.get('/notifications/settings');
    return NotificationSettings.fromJson(
        response['data'] as Map<String, dynamic>);
  }

  Future<void> updateSettings(NotificationSettings settings) async {
    await _api.patch('/notifications/settings', body: settings.toJson());
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ApiClient.instance);
});
