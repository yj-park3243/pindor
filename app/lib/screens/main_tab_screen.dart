import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/router.dart';
import '../config/theme.dart';
import '../providers/notification_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/matching_provider.dart';
import '../repositories/matching_repository.dart';
import '../providers/chat_provider.dart';
import '../widgets/common/in_app_notification.dart';
import '../widgets/common/app_toast.dart';
import '../core/network/api_client.dart';
import '../core/network/socket_service.dart';
import '../models/pin.dart';
import 'profile/profile_screen.dart' show selectedPinProvider;

/// 메인 탭 네비게이션 화면
class MainTabScreen extends ConsumerStatefulWidget {
  final Widget child;

  const MainTabScreen({super.key, required this.child});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> with WidgetsBindingObserver {
  Timer? _pendingMatchPoller;
  StreamSubscription<bool>? _socketStateSub;
  final Set<String> _autoNavigatedMatchIds = {};
  static const _tabRoutes = [
    AppRoutes.home,
    AppRoutes.map,
    AppRoutes.matchList,
    AppRoutes.profile,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupSocketNotificationListener();
    _startPendingMatchPolling();
    _listenSocketReconnect();
    // 자주 가는 핀이 없으면 무조건 핀 설정 화면으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFavoritePin());
  }

  /// 자주 가는 핀이 DB에도 없을 때만 location-setup으로 강제 이동.
  /// SharedPreferences 캐시가 있어도 selectedPinProvider state를 명시적으로 갱신해야
  /// 화면들이 핀을 즉시 인식한다. (Notifier.build()→_load() 비동기 race를 회피)
  Future<void> _ensureFavoritePin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('selected_pin');

      // 1) 캐시 있으면 즉시 provider state 복원 (앱 재시작 시 핵심)
      if (cached != null && cached.isNotEmpty) {
        try {
          final cachedPin = Pin.fromJson(jsonDecode(cached) as Map<String, dynamic>);
          if (mounted) {
            // notifier.select()는 SharedPreferences 재저장 + 서버 sync까지 처리.
            // 여기선 state만 업데이트하면 충분하므로 직접 state 세팅.
            ref.read(selectedPinProvider.notifier).restoreFromCache(cachedPin);
            debugPrint('[MainTab] 캐시 favorite pin 복원 — pinId=${cachedPin.id}');
          }
        } catch (e) {
          debugPrint('[MainTab] 캐시 pin 파싱 실패: $e — 캐시 무시하고 서버 조회');
          await prefs.remove('selected_pin');
        }
        // 캐시 정상이면 서버 호출 생략하고 통과
        if (cached.isNotEmpty) return;
      }

      // 2) 캐시 없음 → 서버 조회
      final response = await ApiClient.instance.get('/pins/favorite');
      final data = response is Map ? response['data'] : null;
      debugPrint('[MainTab] /pins/favorite 응답 data 타입=${data.runtimeType}');

      if (data == null) {
        if (mounted) {
          debugPrint('[MainTab] DB에도 자주 가는 핀 없음 — location-setup으로 강제 이동');
          context.go(AppRoutes.locationSetup);
        }
        return;
      }

      if (data is Map<String, dynamic>) {
        try {
          final pin = Pin.fromJson(data);
          if (mounted) {
            await ref.read(selectedPinProvider.notifier).select(pin);
            debugPrint('[MainTab] 자주 가는 핀 DB에서 복원 — pinId=${pin.id}, name=${pin.name}');
          }
        } catch (e) {
          debugPrint('[MainTab] favorite pin 파싱 실패(강제 이동 안 함): $e — 원본=$data');
        }
      }
    } catch (e) {
      debugPrint('[MainTab] favorite pin 체크 실패(강제 이동 안 함): $e');
    }
  }

  @override
  void dispose() {
    _pendingMatchPoller?.cancel();
    _socketStateSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 소켓 재연결 직후 매칭 목록 force refresh — 끊긴 동안 놓친 PENDING_ACCEPT 보정
  void _listenSocketReconnect() {
    _socketStateSub?.cancel();
    bool wasConnected = SocketService.instance.isConnected;
    _socketStateSub = SocketService.instance.onConnectionState.listen((connected) {
      // false → true 전이만 처리 (재연결 시점)
      if (!wasConnected && connected) {
        debugPrint('[MainTab] 소켓 재연결 감지 — 매칭 목록 force refresh');
        _checkPendingMatchAndNavigate();
      }
      wasConnected = connected;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // foreground 복귀 시:
      // 1) 끊긴 소켓 즉시 재연결 (백그라운드 동안 OS가 끊었을 가능성)
      // 2) 매칭 목록 force refresh로 socket이 놓친 PENDING_ACCEPT 보정
      _ensureSocketConnected();
      _checkPendingMatchAndNavigate();
    }
  }

  /// 소켓이 끊겨 있으면 즉시 재연결 시도 (토큰 보유 시).
  /// syncSocketConnection 내부 디바운스로 중복 호출 안전.
  Future<void> _ensureSocketConnected() async {
    if (SocketService.instance.isConnected) return;
    try {
      await syncSocketConnection(ref);
    } catch (e) {
      debugPrint('[MainTab] 소켓 재연결 실패: $e');
    }
  }

  /// 소켓 연결 안전망 — 5분마다 소켓이 살아있는지만 확인.
  /// 소켓이 healthy하면 아무 API 호출도 발생하지 않는다.
  /// 끊겨있으면 재연결 시도 → 재연결 성공 시 _listenSocketReconnect 가 force refresh 트리거.
  ///
  /// 매칭 목록 force refresh는 다음 경로로만 발생한다:
  ///  1) didChangeAppLifecycleState(resumed) — 앱 포그라운드 복귀
  ///  2) _listenSocketReconnect — 소켓 재연결 직후
  ///  3) 소켓 notification 이벤트 (MATCH_PENDING_ACCEPT 등)
  ///  4) FCM 푸시 (백그라운드 포함)
  void _startPendingMatchPolling() {
    _pendingMatchPoller?.cancel();
    _pendingMatchPoller = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!SocketService.instance.isConnected) {
        await _ensureSocketConnected();
      }
    });
  }

  Future<void> _checkPendingMatchAndNavigate() async {
    if (!mounted) return;
    final loc = GoRouterState.of(context).matchedLocation;
    // 이미 매칭 관련 화면에 있으면 자동 이동 X (사용자 컨텍스트 보존)
    if (loc.startsWith('/matches/') || loc.startsWith('/chats/')) return;

    try {
      ref.read(matchListForceRefreshProvider.notifier).state = true;
      ref.invalidate(matchListProvider(null));
      // matchListProvider가 갱신되면 ref.listen에서 자동 이동 처리됨
    } catch (_) {}
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
            final matchId = data['data']?['matchId'] as String?;
            debugPrint('[Match] MATCH_PENDING_ACCEPT 수신 — matchId=$matchId → 수락 화면 이동');
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            // addPostFrameCallback: 열린 sheet/dialog와의 Navigator dispose 충돌 방지
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (matchId != null) {
                context.go('/matches/$matchId/accept');
              } else {
                context.go(AppRoutes.matchList);
              }
            });
            ref.read(notificationListProvider.notifier).addNotification(data);
            return;
          }

          debugPrint('[Match] 소켓 알림 수신 type=$type matchId=${data['data']?['matchId']}');

          // 양측 수락 완료 — 매칭 확정, 목록 갱신 + 상세 화면 이동
          if (type == 'MATCH_BOTH_ACCEPTED') {
            final matchId = data['data']?['matchId'] as String?;
            debugPrint('[Match] 상대 수락 완료 (MATCH_BOTH_ACCEPTED) — matchId=$matchId');
            ref.invalidate(matchRequestProvider);
            // 캐시 무시하고 서버에서 직접 가져오도록 강제 갱신
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            if (matchId != null) {
              ref.invalidate(matchDetailProvider(matchId));
            }
            AppToast.success('매칭이 확정되었습니다!');
            if (matchId != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.go('/matches/$matchId');
              });
            }
            ref.read(notificationListProvider.notifier).addNotification(data);
            return;
          }

          // 매칭 완료 — 완료 탭으로 이동
          if (type == 'MATCH_COMPLETED') {
            final matchId = data['data']?['matchId'] as String?;
            debugPrint('[Match] 매칭 완료 (MATCH_COMPLETED) — matchId=$matchId');
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            if (matchId != null) ref.invalidate(matchDetailProvider(matchId));
            ref.read(notificationListProvider.notifier).addNotification(data);
            AppToast.success('경기가 완료되었습니다!');
            // 다음 프레임에 이동 (Navigator dispose 잠금 충돌 방지: _debugLocked assertion)
            // bottom sheet/dialog가 자체적으로 pop 중일 때 즉시 go() 하면 NavigatorState
            // dispose 도중 _debugLocked assertion 발생 → addPostFrameCallback으로 지연.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/matches', extra: {'initialTab': 1});
            });
            return;
          }

          // 매칭 취소/거절 — 목록 갱신
          if (type == 'MATCH_CANCELLED' || type == 'MATCH_REJECTED' || type == 'MATCH_ACCEPT_TIMEOUT') {
            final matchId = data['data']?['matchId'] as String?;
            debugPrint('[Match] $type 수신 — matchId=$matchId');
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
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
      ref.listenManual(socketMatchFoundProvider, (previous, next) {
        next.whenData((data) {
          final matchId = data['matchId'] as String?;
          debugPrint('[Match] MATCH_FOUND 수신 — matchId=$matchId');
          if (matchId != null && mounted) {
            _autoNavigatedMatchIds.add(matchId);
            SocketService.instance.joinMatch(matchId);
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            context.go('/matches/$matchId/accept');
          }
        });
      });

      // 매칭 목록 변경 listen — socket 누락 fallback.
      // 새 PENDING_ACCEPT 매칭이 발견되면 accept 페이지로 자동 이동.
      ref.listenManual(matchListProvider(null), (prev, next) {
        next.whenData((matches) {
          if (!mounted) return;
          final loc = GoRouterState.of(context).matchedLocation;
          // 이미 매칭/채팅 화면에 있으면 자동 이동 X
          if (loc.startsWith('/matches/') || loc.startsWith('/chats/')) return;
          for (final m in matches) {
            if (m.status != 'PENDING_ACCEPT') continue;
            // 이미 본인이 수락한 상태면 자동 이동 X (상대 응답 대기 중)
            final myAccepted = m.acceptances?.any((a) => a.accepted == true) ?? false;
            if (myAccepted) continue;
            // 한 번 자동 이동한 ID는 중복 이동 안 함
            if (_autoNavigatedMatchIds.contains(m.id)) continue;
            debugPrint('[Match] PENDING_ACCEPT 폴링 fallback 감지 — matchId=${m.id} → 수락 화면 이동');
            _autoNavigatedMatchIds.add(m.id);
            context.go('/matches/${m.id}/accept');
            break;
          }
        });
      });

      // MATCH_STATUS_CHANGED — 소켓 룸 기반 매칭 상태 변경 알림
      ref.listenManual(socketMatchStatusChangedProvider, (previous, next) {
        next.whenData((data) {
          final matchId = data['matchId'] as String?;
          final status = data['status'] as String?;
          debugPrint('[Match] MATCH_STATUS_CHANGED 수신 — matchId=$matchId status=$status');

          if (matchId != null) {
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchDetailProvider(matchId));
          }

          // 자동 redirect는 사용자가 매칭 화면에 있을 때만 수행 (다른 화면에서 튕김 방지).
          // 케이스:
          //  A) accept 페이지에 있는 사용자 — 양측 수락 완료, 즉시 상세로 이동
          //  B) 매칭 목록에 있는 사용자 — 본인이 먼저 수락 후 목록으로 돌아간 케이스, 상세로 이동
          //  C) 그 외 화면(홈/핀/마이/다른 매칭 상세 등) — 무시
          if (status == 'CHAT' && matchId != null && mounted) {
            final loc = GoRouterState.of(context).matchedLocation;
            final shouldNavigate = loc == '/matches/$matchId/accept' || loc == '/matches';
            if (shouldNavigate) {
              AppToast.success('매칭이 확정되었습니다! 🎉');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.go('/matches/$matchId');
              });
            }
          }

          if (status == 'COMPLETED' && matchId != null) {
            SocketService.instance.leaveMatch(matchId);
          }

          if (status == 'CANCELLED' && matchId != null) {
            SocketService.instance.leaveMatch(matchId);
          }
        });
      });
    });
  }

  void _onTabTap(int index) {
    syncSocketConnection(ref);
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

    return AdaptiveScaffold(
      minimizeBehavior: TabBarMinimizeBehavior.never,
      body: widget.child,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        useNativeBottomBar: true,
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
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: _onTabTap,
          backgroundColor: const Color(0xFF0A0A0A),
          indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.15),
          height: 64,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primaryColor),
              label: '홈',
            ),
            NavigationDestination(
              icon: const Icon(Icons.location_on_outlined),
              selectedIcon: Icon(Icons.location_on_rounded, color: AppTheme.primaryColor),
              label: '핀',
            ),
            NavigationDestination(
              icon: unreadCount > 0
                  ? Badge(label: Text('$unreadCount'), child: const Icon(Icons.sports_esports_outlined))
                  : const Icon(Icons.sports_esports_outlined),
              selectedIcon: unreadCount > 0
                  ? Badge(label: Text('$unreadCount'), child: Icon(Icons.sports_esports_rounded, color: AppTheme.primaryColor))
                  : Icon(Icons.sports_esports_rounded, color: AppTheme.primaryColor),
              label: '매칭',
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded, color: AppTheme.primaryColor),
              label: '마이',
            ),
          ],
        ),
      ),
    );
  }
}
