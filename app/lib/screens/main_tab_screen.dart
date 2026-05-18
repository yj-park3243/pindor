import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/router.dart';
import '../config/theme.dart';
import '../providers/notification_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/matching_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/pin_provider.dart';
import '../providers/ranking_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/active_match_rooms_provider.dart';
import '../core/push/badge_service.dart';
import '../core/version/version_check_service.dart';
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
  final StatefulNavigationShell navigationShell;

  const MainTabScreen({super.key, required this.navigationShell});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> with WidgetsBindingObserver {
  Timer? _pendingMatchPoller;
  StreamSubscription<bool>? _socketStateSub;
  final Set<String> _autoNavigatedMatchIds = {};
  DateTime? _lastBackPressed;

  Future<bool> _handleAndroidBack() async {
    // 자식 라우트가 푸시되어 있으면 그대로 pop (기본 동작)
    if (GoRouter.of(context).canPop()) return false;
    final now = DateTime.now();
    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      AppToast.info('한 번 더 누르면 종료됩니다');
      return true; // 백 이벤트 소비 — 앱 종료 안 됨
    }
    await SystemNavigator.pop();
    return true;
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupSocketNotificationListener();
    _startPendingMatchPolling();
    _listenSocketReconnect();
    // 자주 가는 핀이 없으면 무조건 핀 설정 화면으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureFavoritePin();
      // 앱 진입 시 unread count 채워두기 — 매칭 카드/탭 배지 표시용
      try {
        refreshUnreadCounts(ref);
      } catch (_) {}
      // 앱 진입 시 디바이스 배지/전달된 알림 초기화
      BadgeService.instance.clear();
    });
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
      // 2) 매칭 목록 + 채팅방(unread) 강제 갱신 → 백그라운드 동안 놓친 데이터 보정
      _ensureSocketConnected();
      _checkPendingMatchAndNavigate();
      try {
        ref.invalidate(chatRoomListProvider);
        refreshUnreadCounts(ref);
      } catch (_) {}
      // 앱 진입 시 디바이스 배지/전달된 알림 초기화
      BadgeService.instance.clear();
      // 백그라운드 동안 운영 측에서 minVersion이 올라갔을 수 있으므로 강제 업데이트 재체크
      try {
        VersionCheckService.check(context);
      } catch (_) {}
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
          debugPrint('[MainTab] socket notification 수신 type=$type matchId=${data['data']?['matchId']}');
          // 채팅방 안에서 발생하는 모든 메시지 알림
          // (텍스트/사진/위치/시스템(숫자뽑기·동전던지기)/게임 결과 입력)
          const chatNotifTypes = {
            'CHAT_MESSAGE',
            'CHAT_IMAGE',
            'CHAT_LOCATION',
            'CHAT_SYSTEM',
            'GAME_RESULT_SUBMITTED',
          };
          if (chatNotifTypes.contains(type)) {
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
                  if (roomId != null) {
                    context.push('/chats/$roomId');
                  } else {
                    // 게임 결과 알림 등 roomId 없으면 deepLink 사용
                    final deepLink = data['data']?['deepLink'] as String?;
                    if (deepLink != null) context.push(deepLink);
                  }
                },
              );
            }
            return;
          }

          // 매칭 성사 알림 — 수락 화면으로 직접 이동
          if (type == 'MATCH_PENDING_ACCEPT') {
            final matchId = data['data']?['matchId'] as String?;
            debugPrint('[Match] MATCH_PENDING_ACCEPT 수신 — matchId=$matchId');
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            ref.read(notificationListProvider.notifier).addNotification(data);

            if (matchId != null && _autoNavigatedMatchIds.contains(matchId)) {
              debugPrint('[Match] MATCH_PENDING_ACCEPT 이미 처리됨 — skip');
              return;
            }
            // addPostFrameCallback: 열린 sheet/dialog와의 Navigator dispose 충돌 방지
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (matchId == null) {
                context.go(AppRoutes.matchList);
                return;
              }
              // 이미 accept 화면에 있으면 push 안 함
              final loc = GoRouterState.of(context).matchedLocation;
              if (loc == '/matches/$matchId/accept') {
                _autoNavigatedMatchIds.add(matchId);
                return;
              }
              _autoNavigatedMatchIds.add(matchId);
              debugPrint('[MainTab] go(accept) — from MATCH_PENDING_ACCEPT matchId=$matchId');
              context.go('/matches/$matchId/accept');
            });
            return;
          }

          debugPrint('[Match] 소켓 알림 수신 type=$type matchId=${data['data']?['matchId']}');

          // 양측 수락 완료 — 매칭 확정, 목록 갱신 + 상세 화면 이동
          // 우리 만났어요 — 상대 confirm 알림 (socket 룸 누락 fallback)
          if (type == 'MATCH_MET_UPDATED') {
            final matchId = data['data']?['matchId'] as String?;
            debugPrint('[Match] MATCH_MET_UPDATED 수신 — matchId=$matchId');
            if (matchId != null) {
              ref.invalidate(matchDetailProvider(matchId));
              ref.read(matchListForceRefreshProvider.notifier).state = true;
              ref.invalidate(matchListProvider(null));
            }
            ref.read(notificationListProvider.notifier).addNotification(data);
            return;
          }

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
            // 매칭 종료 → 해당 채팅방의 미읽음 배지를 즉시 0으로
            // (매치 목록 invalidate 전에 캐시에서 chatRoomId 추출)
            if (matchId != null) {
              final cached = ref.read(matchListProvider(null)).valueOrNull;
              if (cached != null) {
                for (final m in cached) {
                  if (m.id == matchId && m.chatRoomId.isNotEmpty) {
                    clearUnread(ref, m.chatRoomId);
                    break;
                  }
                }
              }
            }
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            if (matchId != null) ref.invalidate(matchDetailProvider(matchId));
            ref.read(notificationListProvider.notifier).addNotification(data);
            unawaited(refreshUnreadCounts(ref));
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
            // 매칭 종료 → 해당 채팅방의 미읽음 배지를 즉시 0으로
            // (매치 목록 invalidate 전에 캐시에서 chatRoomId 추출)
            if (matchId != null) {
              final cached = ref.read(matchListProvider(null)).valueOrNull;
              if (cached != null) {
                for (final m in cached) {
                  if (m.id == matchId && m.chatRoomId.isNotEmpty) {
                    clearUnread(ref, m.chatRoomId);
                    break;
                  }
                }
              }
            }
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
            if (matchId != null) ref.invalidate(matchDetailProvider(matchId));
            ref.read(notificationListProvider.notifier).addNotification(data);
            unawaited(refreshUnreadCounts(ref));
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
          if (matchId == null || !mounted) return;
          // 같은 matchId 중복 navigation 차단 (무한 루프 방지)
          if (_autoNavigatedMatchIds.contains(matchId)) {
            debugPrint('[Match] MATCH_FOUND 이미 처리됨 — skip');
            return;
          }
          // 이미 accept 화면에 있으면 다시 push 안 함
          final loc = GoRouterState.of(context).matchedLocation;
          if (loc == '/matches/$matchId/accept') {
            _autoNavigatedMatchIds.add(matchId);
            return;
          }
          _autoNavigatedMatchIds.add(matchId);
          SocketService.instance.joinMatch(matchId);
          ref.invalidate(matchListProvider(null));
          ref.invalidate(matchRequestProvider);
          debugPrint('[MainTab] go(accept) — from MATCH_FOUND matchId=$matchId');
          context.go('/matches/$matchId/accept');
        });
      });

      // 매칭 목록 변경 listen — socket 누락 fallback + 활성 매칭 룸 동기화
      ref.listenManual(matchListProvider(null), (prev, next) {
        next.whenData((matches) {
          if (!mounted) return;

          // 활성 매칭(PENDING_ACCEPT/CHAT/CONFIRMED) 룸 join 상태를 글로벌 매니저로 동기화.
          // 화면별 join/leave에 의존하지 않고 앱 런타임 내내 룸 유지.
          ref.read(activeMatchRoomsProvider.notifier).sync(matches);

          // 새 PENDING_ACCEPT 매칭이 발견되면 accept 페이지로 자동 이동.
          final loc = GoRouterState.of(context).matchedLocation;
          if (loc.startsWith('/matches/') || loc.startsWith('/chats/')) return;
          final myUserId = ref.read(currentUserProvider)?.id;
          for (final m in matches) {
            if (m.status != 'PENDING_ACCEPT') continue;
            // 본인이 이미 수락한 상태면 자동 이동 X (상대 응답 대기 중)
            final myAccepted = myUserId != null &&
                (m.acceptances?.any((a) => a.userId == myUserId && a.accepted == true) ?? false);
            if (myAccepted) continue;
            if (_autoNavigatedMatchIds.contains(m.id)) continue;
            debugPrint('[Match] PENDING_ACCEPT 폴링 fallback 감지 — matchId=${m.id} → 수락 화면 이동');
            _autoNavigatedMatchIds.add(m.id);
            debugPrint('[MainTab] go(accept) — from matchListProvider polling matchId=${m.id}');
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
            // 매치 상태가 바뀌었을 때 로컬 SQLite 캐시가 stale일 수 있으므로
            // 무조건 캐시 비우고 서버에서 강제 재조회.
            try {
              ref.read(matchingRepositoryProvider).clearLocalCache();
            } catch (_) {}
            ref.read(matchListForceRefreshProvider.notifier).state = true;
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchDetailProvider(matchId));
          }

          // 매칭 완료(점수/배치 카운트 변동) 시 홈/프로필 데이터 자동 갱신
          if (status == 'COMPLETED' && matchId != null) {
            ref.invalidate(sportsProfilesProvider);
            ref.invalidate(allPinsProvider);
            // 모든 (pinId, sportType) 조합의 핀 랭킹 캐시 무효화
            ref.invalidate(pinRankingBySportProvider);
            try {
              ref.read(authStateProvider.notifier).refreshUser();
            } catch (_) {}
          }

          // 자동 redirect는 사용자가 매칭 화면에 있을 때만 수행 (다른 화면에서 튕김 방지).
          // 케이스:
          //  A) accept 페이지에 있는 사용자 — 양측 수락 완료, 즉시 상세로 이동
          //  B) 매칭 목록에 있는 사용자 — 본인이 먼저 수락 후 목록으로 돌아간 케이스, 상세로 이동
          //  C) 그 외 화면(홈/핀/마이/다른 매칭 상세 등) — 무시
          if (status == 'CHAT' && matchId != null && mounted) {
            final loc = GoRouterState.of(context).matchedLocation;
            // accept 화면 + 매칭 목록(/matches와 그 자식 경로)에서는 매칭 상세로 자동 이동
            final shouldNavigate = loc == '/matches/$matchId/accept' ||
                loc == '/matches' ||
                loc.startsWith('/matches?');
            debugPrint(
              '[MainTab] MATCH_STATUS_CHANGED CHAT matchId=$matchId loc=$loc shouldNavigate=$shouldNavigate',
            );
            // CHAT 상태가 됐어도 _autoNavigatedMatchIds 는 유지해야 함
            // (PENDING_ACCEPT 폴링이 stale 데이터로 다시 accept으로 push하는 race 차단)
            _autoNavigatedMatchIds.add(matchId);
            if (shouldNavigate) {
              AppToast.success('매칭이 확정되었습니다! 🎉');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.go('/matches/$matchId');
              });
            }
          }

          // 매칭 종료(완료/취소/포기 등) → 채팅방 미읽음 배지 즉시 0
          // 매치 캐시는 위에서 invalidate되었으므로 valueOrNull은 직전 값을 반환
          if ((status == 'COMPLETED' || status == 'CANCELLED') &&
              matchId != null) {
            final cached = ref.read(matchListProvider(null)).valueOrNull;
            if (cached != null) {
              for (final m in cached) {
                if (m.id == matchId && m.chatRoomId.isNotEmpty) {
                  clearUnread(ref, m.chatRoomId);
                  break;
                }
              }
            }
            unawaited(refreshUnreadCounts(ref));
          }

          if (status == 'COMPLETED' && matchId != null) {
            SocketService.instance.leaveMatch(matchId);
          }

          if (status == 'CANCELLED' && matchId != null) {
            SocketService.instance.leaveMatch(matchId);
            // 거절(REJECTED)은 -5점 페널티가 있으므로 점수/랭킹도 새로고침 없이 갱신
            if (data['reason'] == 'REJECTED') {
              ref.invalidate(sportsProfilesProvider);
              ref.invalidate(pinRankingBySportProvider);
              try {
                ref.read(authStateProvider.notifier).refreshUser();
              } catch (_) {}
            }
          }
        });
      });
    });
  }

  void _onTabTap(int index) {
    syncSocketConnection(ref);
    // 같은 탭 재탭 시 해당 branch의 root로 pop, 다른 탭은 보던 화면 유지
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final unreadCount = ref.watch(totalUnreadCountProvider);

    return BackButtonListener(
      onBackButtonPressed: _handleAndroidBack,
      child: AdaptiveScaffold(
      minimizeBehavior: TabBarMinimizeBehavior.never,
      body: widget.navigationShell,
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
      ),
    );
  }
}
