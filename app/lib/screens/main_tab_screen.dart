import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../config/router.dart';
import '../providers/notification_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/matching_provider.dart';
import '../repositories/matching_repository.dart';
import '../providers/chat_provider.dart';
import '../widgets/common/in_app_notification.dart';

/// 메인 탭 네비게이션 화면
class MainTabScreen extends ConsumerStatefulWidget {
  final Widget child;

  const MainTabScreen({super.key, required this.child});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> {
  static const _tabRoutes = [
    AppRoutes.home,
    AppRoutes.map,
    AppRoutes.matchList,
    AppRoutes.profile,
  ];

  @override
  void initState() {
    super.initState();
    _setupSocketNotificationListener();
  }

  void _setupSocketNotificationListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(socketNotificationProvider, (previous, next) {
        next.whenData((data) {
          final type = data['type'] as String? ?? '';
          if (type == 'CHAT_MESSAGE' || type == 'CHAT_IMAGE') {
            // 서버에서 최신 unreadCount 조회
            refreshUnreadCounts(ref);
            return;
          }

          // 매칭 성사 알림 — 수락 화면으로 직접 이동
          if (type == 'MATCH_PENDING_ACCEPT') {
            if (mounted) {
              ref.read(matchingRepositoryProvider).clearLocalCache();
              ref.invalidate(matchListProvider(null));
              ref.invalidate(matchRequestProvider);
              final matchId = data['data']?['matchId'] as String?;
              if (matchId != null) {
                context.go('/matches/$matchId/accept');
              } else {
                context.go(AppRoutes.matchList);
              }
            }
            ref.read(notificationListProvider.notifier).addNotification(data);
            return;
          }

          // 매칭 완료/취소 — 목록 + 상세 즉시 갱신
          if (type == 'MATCH_COMPLETED' || type == 'MATCH_CANCELLED') {
            ref.read(matchingRepositoryProvider).clearLocalCache();
            ref.invalidate(matchListProvider(null));
            final matchId = data['data']?['matchId'] as String?;
            if (matchId != null) {
              ref.invalidate(matchDetailProvider(matchId));
            }
            ref.read(notificationListProvider.notifier).addNotification(data);
            return;
          }

          if (mounted) {
            InAppNotificationManager.show(
              context,
              title: data['title'] as String? ?? '알림',
              body: data['body'] as String? ?? '',
              onTap: () {
                final deepLink = data['data']?['deepLink'] as String?;
                if (deepLink != null) {
                  context.go(deepLink);
                }
              },
            );
          }

          ref.read(notificationListProvider.notifier).addNotification(data);
        });
      });
    });
  }

  void _onTabTap(int index) {
    context.go(_tabRoutes[index]);
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/map')) return 1;
    if (location.startsWith('/matches')) return 2;
    if (location.startsWith('/profile') || location.startsWith('/teams')) {
      return 3;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);
    final unreadCount = ref.watch(totalUnreadCountProvider);

    // AdaptiveScaffold는 body 위에 바텀 네비를 overlay하므로
    // 하단 패딩을 추가하여 콘텐츠가 가려지지 않도록 함
    final bottomPadding = MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 16;

    return AdaptiveScaffold(
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: MediaQuery.of(context).padding.copyWith(bottom: bottomPadding),
        ),
        child: widget.child,
      ),
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: currentIndex,
        onTap: _onTabTap,
        items: [
          const AdaptiveNavigationDestination(
            icon: 'house.fill',
            label: '홈',
          ),
          const AdaptiveNavigationDestination(
            icon: 'mappin.and.ellipse',
            label: '핀',
          ),
          AdaptiveNavigationDestination(
            icon: 'sportscourt.fill',
            label: '매칭',
            badgeCount: unreadCount > 0 ? unreadCount : null,
          ),
          const AdaptiveNavigationDestination(
            icon: 'person.fill',
            label: '마이',
          ),
        ],
      ),
    );
  }
}
