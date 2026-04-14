import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../config/router.dart';
import '../providers/notification_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/matching_provider.dart';
import '../repositories/matching_repository.dart';
import '../providers/chat_provider.dart';
import '../widgets/common/in_app_notification.dart';
import '../widgets/common/app_toast.dart';
import '../core/network/socket_service.dart';

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
            // 현재 열린 채팅방이 아닐 때만 인앱 토스트 표시
            final roomId = data['data']?['roomId'] as String?;
            final isInThisRoom = roomId != null && SocketService.instance.activeRoomId == roomId;
            if (!isInThisRoom && mounted) {
              InAppNotificationManager.show(
                context,
                title: data['title'] as String? ?? '새 메시지',
                body: data['body'] as String? ?? '',
                onTap: () {
                  if (roomId != null) context.push('/chats/$roomId');
                },
              );
            }
            return;
          }

          // 매칭 성사 알림 — 수락 화면으로 직접 이동
          if (type == 'MATCH_PENDING_ACCEPT') {
            if (mounted) {
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

          debugPrint('[MainTab] 소켓 알림 수신: type=$type');

          // 양측 수락 완료 — 매칭 확정, 목록 갱신 + 상세 화면 이동
          if (type == 'MATCH_BOTH_ACCEPTED') {
            final matchId = data['data']?['matchId'] as String?;
            ref.invalidate(matchRequestProvider);
            // 캐시 무시하고 서버에서 직접 가져오도록 강제 갱신
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            if (matchId != null) {
              ref.invalidate(matchDetailProvider(matchId));
            }
            AppToast.success('매칭이 확정되었습니다!');
            if (matchId != null && mounted) {
              context.go('/matches/$matchId');
            }
            ref.read(notificationListProvider.notifier).addNotification(data);
            return;
          }

          // 매칭 완료 — 완료 탭으로 이동
          if (type == 'MATCH_COMPLETED') {
            final matchId = data['data']?['matchId'] as String?;
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            if (matchId != null) ref.invalidate(matchDetailProvider(matchId));
            ref.read(notificationListProvider.notifier).addNotification(data);
            AppToast.success('경기가 완료되었습니다!');
            if (mounted) context.go('/matches', extra: {'initialTab': 1});
            return;
          }

          // 매칭 취소/거절 — 목록 갱신
          if (type == 'MATCH_CANCELLED' || type == 'MATCH_REJECTED' || type == 'MATCH_ACCEPT_TIMEOUT') {
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            final matchId = data['data']?['matchId'] as String?;
            if (matchId != null) ref.invalidate(matchDetailProvider(matchId));
            ref.read(notificationListProvider.notifier).addNotification(data);
            if (type == 'MATCH_ACCEPT_TIMEOUT') {
              AppToast.warning('매칭 수락 시간이 만료되었습니다');
            } else if (type == 'MATCH_REJECTED' && mounted) {
              AppToast.info('매칭이 취소되었습니다');
              InAppNotificationManager.show(
                context,
                title: data['title'] as String? ?? '매칭 취소',
                body: data['body'] as String? ?? '',
                onTap: () => context.go(AppRoutes.matchList),
              );
            } else if (type == 'MATCH_CANCELLED') {
              AppToast.info('매칭이 취소되었습니다');
            }
            return;
          }

          // 점수 변동 / 결과 제출 — matchDetail만 갱신 (무한 루프 방지)
          if (type == 'SCORE_UPDATED' || type == 'GAME_RESULT_SUBMITTED') {
            final matchId = data['data']?['matchId'] as String?;
            if (matchId != null) ref.invalidate(matchDetailProvider(matchId));
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

      // MATCH_FOUND — 소켓 룸 기반 매칭 성사 알림
      // matchrequest:{requestId} 룸에서 실시간으로 수신
      ref.listenManual(socketMatchFoundProvider, (previous, next) {
        next.whenData((data) {
          final matchId = data['matchId'] as String?;
          if (matchId != null && mounted) {
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            context.go('/matches/$matchId/accept');
          }
        });
      });

      // MATCH_STATUS_CHANGED — 소켓 룸 기반 매칭 상태 변경 알림
      // match:{matchId} 룸에서 실시간으로 수신
      ref.listenManual(socketMatchStatusChangedProvider, (previous, next) {
        next.whenData((data) {
          final matchId = data['matchId'] as String?;
          final status = data['status'] as String?;

          if (matchId != null) {
            // 캐시 무시하고 서버에서 직접 가져오도록 강제 갱신
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchDetailProvider(matchId));
          }

          // 양측 수락 완료 → 매칭 상세 화면으로 이동
          if (status == 'CHAT' && matchId != null && mounted) {
            AppToast.success('상대방이 수락했습니다!');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/matches/$matchId');
            });
          }

          // 매칭 완료 → 완료 탭으로 이동
          if (status == 'COMPLETED' && matchId != null) {
            SocketService.instance.leaveMatch(matchId);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/matches', extra: {'initialTab': 1});
            });
          }

          // 매칭 취소 → 룸 퇴장
          if (status == 'CANCELLED' && matchId != null) {
            SocketService.instance.leaveMatch(matchId);
          }
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
      minimizeBehavior: TabBarMinimizeBehavior.never,
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
          AdaptiveNavigationDestination(
            icon: Platform.isIOS ? 'house.fill' : Symbols.home_rounded,
            label: '홈',
          ),
          AdaptiveNavigationDestination(
            icon: Platform.isIOS ? 'mappin.and.ellipse' : Symbols.location_on_rounded,
            label: '핀',
          ),
          AdaptiveNavigationDestination(
            icon: Platform.isIOS ? 'sportscourt.fill' : Symbols.stadium_rounded,
            label: '매칭',
            badgeCount: unreadCount > 0 ? unreadCount : null,
          ),
          AdaptiveNavigationDestination(
            icon: Platform.isIOS ? 'person.fill' : Symbols.person_rounded,
            label: '마이',
          ),
        ],
      ),
    );
  }
}
