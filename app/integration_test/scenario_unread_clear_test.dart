import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spots/main.dart' as app;
import 'package:spots/widgets/common/app_toast.dart';

import 'helpers/api_helper.dart';
import 'helpers/test_config.dart';

void _forceGo(String path) {
  final ctx = AppToast.navigatorKey.currentContext;
  if (ctx != null) {
    try {
      GoRouter.of(ctx).go(path);
    } catch (_) {}
  }
}

Future<void> _settle(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 200);
  var elapsed = Duration.zero;
  while (elapsed < d) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 60,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.pump(interval);
  }
  return false;
}

Future<bool> _waitGone(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 30,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    if (finder.evaluate().isEmpty) return true;
    await tester.pump(interval);
  }
  return false;
}

final Dio _shotDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 2),
  receiveTimeout: const Duration(seconds: 3),
));

Future<void> _shot(String name) async {
  try {
    await _shotDio.get('http://127.0.0.1:9998/userA_$name');
    await Future.delayed(const Duration(milliseconds: 600));
  } catch (_) {}
}

/// 시나리오 — 매칭 종료 시 채팅 미읽음 배지 즉시 초기화
///
/// 검증:
///   1. A,B CHAT 상태 진입
///   2. B 가 메시지 전송 → A 매칭 카드에 unread 배지(1) 표시
///   3. B 가 forfeit → 매치 COMPLETED
///   4. A 매칭 카드의 unread 배지가 즉시 사라짐 (새로고침/재진입 없이)
///
/// 단일 시뮬(A)만 사용. B 의 모든 액션은 ApiHelper 로 외부 트리거.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiHelper();

  const accessToken = String.fromEnvironment('TEST_ACCESS_TOKEN');
  const refreshToken = String.fromEnvironment('TEST_REFRESH_TOKEN');
  const userId = String.fromEnvironment('TEST_USER_ID');
  const opponentToken =
      String.fromEnvironment('TEST_OPPONENT_ACCESS_TOKEN');
  const pinName = String.fromEnvironment(
    'SCENARIO_PIN_NAME',
    defaultValue: TestConfig.testPinName,
  );

  testWidgets(
    '매칭 종료 시 unread 배지 즉시 초기화',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      expect(opponentToken.isNotEmpty, true,
          reason: 'TEST_OPPONENT_ACCESS_TOKEN 필수');
      debugPrint('[UC] 시작 userId=$userId');

      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      await storage.deleteAll();
      await storage.write(key: 'access_token', value: accessToken);
      if (refreshToken.isNotEmpty) {
        await storage.write(key: 'refresh_token', value: refreshToken);
      }
      await storage.write(key: 'user_id', value: userId);

      // ── phase 1: 양쪽 매칭 요청 (앱 기동 전) ──
      final pins = await api.getAllPins(accessToken);
      final pin = pins.firstWhere(
        (p) => p['name'] == pinName,
        orElse: () => pins.first,
      );
      final pinId = pin['id'] as String;
      await api.createMatchRequest(
        accessToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'unread-clear A',
      );
      await api.createMatchRequest(
        opponentToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'unread-clear B',
      );
      debugPrint('[UC] 양쪽 매칭 요청 생성');

      // ── phase 2: 앱 기동 ──
      unawaited(Future(() => app.main()));
      bool appReady = false;
      for (var i = 0; i < 60; i++) {
        try {
          await _settle(tester, const Duration(milliseconds: 800));
        } catch (_) {
          await tester.pump(const Duration(seconds: 1));
        }
        if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty ||
            find
                .byKey(const Key('match_accept_accept_btn'))
                .evaluate()
                .isNotEmpty) {
          appReady = true;
          break;
        }
      }
      expect(appReady, true, reason: '앱 기동 실패');
      debugPrint('[UC] 앱 기동 완료');
      await _shot('01_app_ready');

      // ── phase 3: 매칭 성사 폴링 + 양쪽 수락 ──
      final pending = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) =>
                  ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(m['status']))
              .toList();
          if (f.isEmpty) throw Exception('no match yet');
          return f.first;
        },
        condition: (m) => true,
        maxAttempts: 60,
      );
      final matchId = pending['id'] as String;
      debugPrint('[UC] 매칭 잡힘 — matchId=$matchId status=${pending['status']}');

      // 양쪽 수락 (이미 CHAT 인 경우 무해)
      try {
        await api.acceptMatch(accessToken, matchId);
      } catch (_) {}
      try {
        await api.acceptMatch(opponentToken, matchId);
      } catch (_) {}

      // CHAT 진입 + chatRoomId 확보
      final chatMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) =>
            ['CHAT', 'CONFIRMED'].contains(m['status'] as String? ?? '') &&
            (m['chatRoomId'] != null &&
                (m['chatRoomId'] as String).isNotEmpty),
        maxAttempts: 60,
      );
      final chatRoomId = chatMatch['chatRoomId'] as String;
      debugPrint('[UC] CHAT 진입 — chatRoomId=$chatRoomId');
      await _shot('02_chat_ready');

      // ── phase 4: B 가 메시지 전송 → A 미읽음 발생 ──
      // 매칭 화면으로 이동 후 카드 배지 검증.
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 3));
      await _shot('03_match_list_before_msg');

      await api.sendMessage(
        opponentToken,
        chatRoomId,
        content: 'unread-clear 테스트 메시지',
      );
      debugPrint('[UC] B 메시지 전송');

      // HTTP sendMessage 는 클라이언트로 socket notification 을 보내지 않으므로,
      // 매칭 화면 pull-to-refresh 로 unread map 강제 갱신을 트리거한다.
      // (RefreshIndicator.onRefresh 에 refreshUnreadCounts 가 포함됨)
      // PENDING_ACCEPT/CHAT 자동 이동으로 매칭 화면을 떠날 수 있어 재시도.
      bool listReady = false;
      for (var i = 0; i < 8; i++) {
        _forceGo('/matches');
        await _settle(tester, const Duration(seconds: 2));
        if (find.byType(RefreshIndicator).evaluate().isNotEmpty) {
          listReady = true;
          break;
        }
      }
      expect(listReady, true,
          reason: '매칭 목록 화면 진입 실패 (RefreshIndicator 미등장)');
      await tester.drag(
          find.byType(RefreshIndicator).first, const Offset(0, 350));
      await _settle(tester, const Duration(seconds: 2));

      // 매칭 카드의 unread 배지 등장 대기
      final badgeFinder =
          find.byKey(ValueKey('match_unread_badge_$matchId'));
      final badgeShown =
          await _waitFor(tester, badgeFinder, maxAttempts: 60);
      await _shot('04_badge_shown');
      expect(badgeShown, true,
          reason: 'B 메시지 후 매칭 카드에 unread 배지가 나타나지 않음');
      debugPrint('[UC] OK 배지(unread=1) 노출 확인');

      // 서버 측 unreadCount 도 1 인지 교차 검증
      final roomsBefore = await api.getChatRooms(accessToken);
      final myRoomBefore = roomsBefore.firstWhere(
        (r) => r['id'] == chatRoomId,
        orElse: () => <String, dynamic>{},
      );
      final unreadBefore =
          (myRoomBefore['unreadCount'] as num?)?.toInt() ?? 0;
      debugPrint('[UC] 서버 unreadCount(전) = $unreadBefore');
      expect(unreadBefore >= 1, true,
          reason: '서버 측 unreadCount 가 1 이상이 아님');

      // ── phase 5: B 가 매칭 취소 → 매치 CANCELLED (종료) ──
      // (staging 정책상 CHAT 상태에서는 forfeit 불가, cancel 만 가능)
      await api.cancelMatch(opponentToken, matchId, reason: 'UC test');
      debugPrint('[UC] B cancel 호출 — 매칭 종료 트리거');

      // ── phase 6: 매칭 카드의 unread 배지가 즉시 사라지는지 검증 ──
      final badgeGone =
          await _waitGone(tester, badgeFinder, maxAttempts: 40);
      await _shot('05_badge_cleared');
      expect(badgeGone, true,
          reason:
              '매칭 종료 후에도 매칭 카드 unread 배지가 남아있음 (즉시 0 처리 실패)');
      debugPrint('[UC] OK 배지 사라짐 확인');

      // 서버 응답도 0 인지 교차 검증 (매치 CANCELLED → unreadCount=0)
      await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) => (m['status'] as String? ?? '') == 'CANCELLED',
        maxAttempts: 40,
      );
      final roomsAfter = await api.getChatRooms(accessToken);
      final myRoomAfter = roomsAfter.firstWhere(
        (r) => r['id'] == chatRoomId,
        orElse: () => <String, dynamic>{},
      );
      // 종료된 매치의 채팅방은 ARCHIVED 일 수도, 단순 unread=0 일 수도 있음
      final unreadAfter =
          (myRoomAfter['unreadCount'] as num?)?.toInt() ?? 0;
      debugPrint('[UC] 서버 unreadCount(후) = $unreadAfter');
      expect(unreadAfter, 0,
          reason: '서버 측 unreadCount 가 0 으로 떨어지지 않음 (서버 회귀)');

      debugPrint('[UC] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
