import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../repositories/notification_repository.dart';

/// 알림 목록 Notifier
class NotificationListNotifier
    extends AutoDisposeAsyncNotifier<List<AppNotification>> {
  String? _cursor;
  bool _hasMore = true;

  @override
  Future<List<AppNotification>> build() async {
    return _fetchNotifications();
  }

  Future<List<AppNotification>> _fetchNotifications() async {
    final repo = ref.read(notificationRepositoryProvider);
    final result = await repo.getNotifications();
    _cursor = result['meta']?['cursor'] as String?;
    _hasMore = result['meta']?['hasMore'] as bool? ?? false;

    return (result['data'] as List<dynamic>)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 더 불러오기
  Future<void> loadMore() async {
    if (!_hasMore) return;

    try {
      final repo = ref.read(notificationRepositoryProvider);
      final result = await repo.getNotifications(cursor: _cursor);
      _cursor = result['meta']?['cursor'] as String?;
      _hasMore = result['meta']?['hasMore'] as bool? ?? false;

      final newNotifications = (result['data'] as List<dynamic>)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();

      final current = state.valueOrNull ?? [];
      state = AsyncData([...current, ...newNotifications]);
    } catch (_) {}
  }

  /// 단건 읽음 처리
  Future<void> markAsRead(String notificationId) async {
    final repo = ref.read(notificationRepositoryProvider);
    await repo.markAsRead(notificationId);

    final current = state.valueOrNull ?? [];
    state = AsyncData(current
        .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
        .toList());
  }

  /// 전체 읽음 처리
  Future<void> markAllAsRead() async {
    final repo = ref.read(notificationRepositoryProvider);
    await repo.markAllAsRead();

    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((n) => n.copyWith(isRead: true)).toList());
  }

  /// 새 알림 추가 (소켓 수신 시)
  void addNotification(Map<String, dynamic> data) {
    final notification = AppNotification(
      id: data['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: '',
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      data: data['data'] as Map<String, dynamic>? ?? {},
      isRead: false,
      createdAt: DateTime.now(),
    );

    final current = state.valueOrNull ?? [];
    state = AsyncData([notification, ...current]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _fetchNotifications());
  }
}

final notificationListProvider = AutoDisposeAsyncNotifierProvider<
    NotificationListNotifier, List<AppNotification>>(
  NotificationListNotifier.new,
);

/// 읽지 않은 알림 수
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationListProvider).valueOrNull ?? [];
  return notifications.where((n) => !n.isRead).length;
});

/// 알림 설정 프로바이더
final notificationSettingsProvider =
    FutureProvider.autoDispose<NotificationSettings>((ref) async {
  final repo = ref.read(notificationRepositoryProvider);
  return repo.getSettings();
});
