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
import 'package:spots/core/network/socket_service.dart';

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

/// 현재 위치가 이미 path 면 go() 를 호출하지 않는다.
/// 매 라운드 무조건 go() 하면 StatefulShellRoute 의 shell 이 중복 재구성되어
/// GlobalKey 충돌 assertion 이 발생한다.
void _forceGoIfNeeded(String path) {
  final ctx = AppToast.navigatorKey.currentContext;
  if (ctx == null) return;
  try {
    if (GoRouterState.of(ctx).matchedLocation == path) return;
    GoRouter.of(ctx).go(path);
  } catch (_) {}
}

/// 단일 pump 는 그 사이 도착한 소켓 이벤트의 state 갱신 → 위젯 rebuild 를
/// 제때 반영하지 못한다. 여러 번 쪼개 pump 하여 rebuild 가 확실히 처리되게 한다.
Future<void> _settle(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 200);
  var elapsed = Duration.zero;
  while (elapsed < d) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// finder 가 트리에 나타날 때까지 폴링.
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

/// 위젯이 나타날 때까지 폴링 후 tap.
Future<bool> _tapKey(
  WidgetTester tester,
  String keyValue, {
  int maxAttempts = 30,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final finder = find.byKey(Key(keyValue));
  for (var i = 0; i < maxAttempts; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      await tester.pump(const Duration(milliseconds: 600));
      return true;
    }
    await tester.pump(interval);
  }
  debugPrint('[WS] _tapKey timeout — key=$keyValue');
  return false;
}

final Dio _shotDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 2),
  receiveTimeout: const Duration(seconds: 3),
));

Future<void> _shot(String role, String name) async {
  try {
    await _shotDio.get('http://127.0.0.1:9998/user${role}_$name');
    await Future.delayed(const Duration(milliseconds: 600));
  } catch (_) {}
}

/// 시나리오 WS — 실시간 소켓 안정성 검증
///
/// 검증 포인트:
///   1. MATCH_FOUND — 매칭 요청 후 수동 개입 없이 accept 화면이 자동 전환되는가
///   2. NEW_MESSAGE — 채팅방에서 상대 메시지가 실시간으로 화면에 표시되는가
///   3. 소켓 복구 — 강제 disconnect 후 룸 재입장으로 채팅이 복구되는가
///
/// 핑퐁 방식: 양쪽이 상대 메시지를 받을 때까지 자기 메시지를 주기적으로 재전송하여
/// 타이밍 동기화 없이 소켓 수신을 검증한다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiHelper();

  const role = String.fromEnvironment('TEST_USER_ROLE', defaultValue: 'A');
  const accessToken = String.fromEnvironment('TEST_ACCESS_TOKEN');
  const refreshToken = String.fromEnvironment('TEST_REFRESH_TOKEN');
  const userId = String.fromEnvironment('TEST_USER_ID');
  const pinName = String.fromEnvironment(
    'SCENARIO_PIN_NAME',
    defaultValue: TestConfig.testPinName,
  );

  const isA = role == 'A';
  const myPing = 'WS-PING-$role';
  const otherPing = isA ? 'WS-PING-B' : 'WS-PING-A';
  const myReconnect = 'WS-RECON-$role';
  const otherReconnect = isA ? 'WS-RECON-B' : 'WS-RECON-A';

  /// 상대 메시지를 받을 때까지 내 메시지를 주기적으로 재전송하는 핑퐁.
  /// maxRounds 가 크면(~2분) A/B 의 채팅방 진입 시차(스크립트상 45초+)를 흡수한다.
  /// 정상 케이스에선 상대 메시지 수신 즉시 return 하므로 빠르게 끝난다.
  ///
  /// 메시지는 반드시 소켓(SEND_MESSAGE)으로 보낸다 — HTTP POST(/chat-rooms/.../messages)는
  /// "fallback"이라 DB 저장만 하고 NEW_MESSAGE 를 emit 하지 않아 상대가 실시간 수신하지 못한다.
  /// 실제 앱의 채팅 입력창도 소켓으로 전송하므로 이게 올바른 경로다.
  Future<bool> pingPong(
    WidgetTester tester,
    String roomId,
    String mySeed,
    String otherSeed, {
    int maxRounds = 120,
  }) async {
    // 상대 핑을 한 번이라도 보면(seen) 성공으로 본다 — 메시지가 계속 쌓이면
    // ListView 스크롤로 viewport 밖으로 밀려나므로, 본 시점을 플래그로 기억한다.
    bool seen = false;
    for (var i = 0; i < maxRounds; i++) {
      // MATCH_BOTH_ACCEPTED 등 소켓 알림이 매칭 상세로 강제 이동시킬 수 있으므로
      // 매 라운드 채팅방으로 복귀시킨다 (이미 채팅방이면 no-op).
      _forceGoIfNeeded('/chats/$roomId');
      try {
        SocketService.instance.sendMessage(roomId, '$mySeed-$i');
      } catch (e) {
        // 미연결 상태 — 다음 라운드에 재시도 (재진입/재연결 후 복구).
        debugPrint('[WS-$role] sendMessage 실패: $e');
      }
      await _settle(tester, const Duration(seconds: 1));
      if (find.textContaining(otherSeed).evaluate().isNotEmpty) {
        seen = true;
      }
      // 상대 핑을 봤고 최소 5라운드 이상 주고받았으면 종료.
      if (seen && i >= 5) return true;
    }
    return seen;
  }

  testWidgets(
    'WS 안정성 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      debugPrint('[WS-$role] 시작 userId=$userId');

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

      // ── phase 1: 매칭 요청 (앱 기동 전) ──
      // 앱 기동 전에 요청을 만들어 두면, 부팅 시 matchRequestProvider.build() 가
      // 이 WAITING 요청을 발견해 joinMatchRequest 를 호출한다 (WS #1 복구 경로 검증).
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
        message: 'WS test $role',
      );
      debugPrint('[WS-$role] 매칭 요청 생성 (앱 기동 전) — pin=${pin['name']}');

      // ── phase 2: 앱 기동 → 부팅 중 WAITING 요청의 socket 룸 자동 복구 ──
      // 앱 기동 시점에 매칭이 이미 성사돼 있으면(상대가 먼저 시작한 경우) 홈이 아니라
      // accept 화면으로 바로 떨어진다 — 둘 다 "앱 정상 기동"으로 간주한다.
      unawaited(Future(() => app.main()));
      bool appReady = false;
      for (var i = 0; i < 60; i++) {
        try {
          await _settle(tester, const Duration(milliseconds: 800));
        } catch (_) {
          await tester.pump(const Duration(seconds: 1));
        }
        if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty ||
            find.byKey(const Key('match_accept_accept_btn')).evaluate().isNotEmpty) {
          appReady = true;
          break;
        }
      }
      expect(appReady, true, reason: '앱 기동 실패 (홈/accept 화면 모두 미도달)');
      debugPrint('[WS-$role] 앱 기동 완료');
      await _shot(role, '01_app_ready');

      // ── phase 3: MATCH_FOUND 자동 수신 검증 ──
      // 수동 네비게이션 없이 accept 화면이 자동으로 떠야 함 = 룸 입장 + MATCH_FOUND 정상.
      final foundAuto = await _waitFor(
        tester,
        find.byKey(const Key('match_accept_accept_btn')),
        maxAttempts: 120,
      );
      await _shot(role, '03_match_found');
      expect(
        foundAuto,
        true,
        reason: 'MATCH_FOUND 소켓 미수신 — accept 화면 자동 전환 실패 (WS 불안정 재현)',
      );
      debugPrint('[WS-$role] OK MATCH_FOUND — accept 화면 자동 전환');

      // ── phase 2: 수락 → CHAT 진입 ──
      final accepted = await _tapKey(tester, 'match_accept_accept_btn');
      expect(accepted, true, reason: '수락 버튼 tap 실패');
      debugPrint('[WS-$role] 수락 tap');
      await _shot(role, '04_accepted');

      final chatMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) => ['CHAT', 'CONFIRMED'].contains(m['status']))
              .toList();
          if (f.isEmpty) throw Exception('not chat yet');
          return f.first;
        },
        condition: (m) => true,
        maxAttempts: 60,
      );
      final matchId = chatMatch['id'] as String;
      final detail = await api.getMatchDetail(accessToken, matchId);
      final roomId = detail['chatRoomId'] as String?;
      expect(
        roomId != null && roomId.isNotEmpty,
        true,
        reason: 'chatRoomId 없음',
      );
      debugPrint('[WS-$role] CHAT 진입 — matchId=$matchId roomId=$roomId');

      // ── phase 3: 채팅방 진입 → 메시지 양방향 수신 검증 ──
      _forceGo('/chats/$roomId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '05_chat_room');

      final gotPing = await pingPong(tester, roomId!, myPing, otherPing);
      await _shot(role, '06_chat_received');
      expect(
        gotPing,
        true,
        reason: 'NEW_MESSAGE 소켓 미수신 — 상대 메시지 "$otherPing" 화면 미표시 (채팅 불안정 재현)',
      );
      debugPrint('[WS-$role] OK NEW_MESSAGE — 상대 메시지 수신');

      // ── phase 4: 소켓 강제 끊김 → 룸 재입장 복구 검증 ──
      // 채팅방을 떠나지 않는다 — chat_provider 의 _connStateSubscription 이
      // 끊김을 감지해 재연결 + joinRoom 을 트리거한다. 라우트 전환을 하면
      // StatefulShell 재구성으로 GlobalKey 충돌이 발생한다.
      SocketService.instance.disconnect();
      debugPrint('[WS-$role] 소켓 강제 disconnect');
      await _settle(tester, const Duration(seconds: 5));
      await _shot(role, '07_chat_rejoined');

      final gotReconnect =
          await pingPong(tester, roomId, myReconnect, otherReconnect);
      await _shot(role, '08_reconnect_received');
      expect(
        gotReconnect,
        true,
        reason: '소켓 재연결 복구 실패 — disconnect 후 상대 메시지 "$otherReconnect" 미수신',
      );
      debugPrint('[WS-$role] OK 소켓 재연결 복구 — 메시지 수신');

      // 위젯 트리 finalize 전에 pending timer(JOIN_ROOM 재시도 등)를 소진시킨다.
      // 남아 있으면 "Timer still pending" assertion 으로 테스트가 실패 처리된다.
      await _settle(tester, const Duration(seconds: 4));
      debugPrint('[WS-$role] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
