import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/router.dart';
import '../providers/notification_provider.dart';
import '../providers/socket_provider.dart';
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
    AppRoutes.chatList,
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
          if (type == 'CHAT_MESSAGE' || type == 'CHAT_IMAGE') return;

          // 매칭 성사 알림 — 배너 없이 즉시 수락 화면으로 이동
          if (type == 'MATCH_PENDING_ACCEPT') {
            final matchId = data['data']?['matchId'] as String?;
            if (matchId != null && mounted) {
              context.go('/matches/$matchId/accept');
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
    if (location.startsWith('/chats')) return 3;
    if (location.startsWith('/profile') || location.startsWith('/teams')) {
      return 4;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: _onTabTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '홈'),
          const BottomNavigationBarItem(icon: Icon(Icons.location_on_rounded), label: '핀'),
          const BottomNavigationBarItem(icon: Icon(Icons.sports_rounded), label: '매칭'),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount', style: const TextStyle(fontSize: 10)),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: '채팅',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: '마이'),
        ],
      ),
    );
  }
}
