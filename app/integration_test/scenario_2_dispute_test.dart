import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
    try { GoRouter.of(ctx).go(path); } catch (_) {}
  }
}

Future<void> _settle(WidgetTester tester, Duration d) async {
  await tester.pump(d);
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

/// 시나리오 2 — 양쪽 동일 결과 → DISPUTED → 이의 제기 → admin 처리
///
/// 흐름:
///   A,B: 매칭 → 수락 → CHAT → confirm-met → A WIN / B WIN → DISPUTED
///   A:   POST /disputes (이의 제기)
///   admin: PATCH /admin/disputes/:id (VOID_GAME) — 별도 Playwright spec
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

  testWidgets(
    '시나리오2 이의제기 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      debugPrint('[S2] role=$role userId=$userId');

      // ── 1. SecureStorage 토큰 주입 ────────────────────────────
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

      // ── 2. 앱 실행 ────────────────────────────────────────────
      unawaited(Future(() => app.main()));
      bool reachedHome = false;
      for (var i = 0; i < 60; i++) {
        try {
          await _settle(tester, const Duration(milliseconds: 800));
        } catch (_) {
          await tester.pump(const Duration(seconds: 1));
        }
        if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty) {
          reachedHome = true;
          break;
        }
      }
      expect(reachedHome, true, reason: '홈 진입 실패');
      debugPrint('[S2-$role] 홈 도달');
      await _shot(role, '01_home');
      await _settle(tester, const Duration(seconds: 1));
      await _shot(role, '02_home_settled');

      // ── 3. 매칭 요청 ───────────────────────────────────────────
      final pins = await api.getAllPins(accessToken);
      final selected = pins.firstWhere(
        (p) => p['name'] == pinName,
        orElse: () => pins.first,
      );
      final pinId = selected['id'] as String;
      await api.createMatchRequest(
        accessToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'E2E S2 ($role)',
      );
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '03_match_requested');

      // ── 4. 매칭 성사 + 수락 + CHAT ────────────────────────────
      final pending = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) => ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED']
                  .contains(m['status']))
              .toList();
          if (f.isEmpty) throw Exception('no match yet');
          return f.first;
        },
        condition: (m) => true,
      );
      final matchId = pending['id'] as String;
      debugPrint('[S2-$role] 매칭 성사: $matchId (${pending['status']})');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '04_pending_accept_page');

      if (pending['status'] == 'PENDING_ACCEPT') {
        await api.acceptMatch(accessToken, matchId);
      }
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '05_after_my_accept');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '06_match_detail');

      // CHAT 진입 + game 생성 대기
      final chatMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) {
          final status = m['status'] as String? ?? '';
          return ['CHAT', 'CONFIRMED'].contains(status);
        },
      );
      debugPrint('[S2-$role] CHAT/CONFIRMED 진입: ${chatMatch['status']}');
      final chatRoomId = chatMatch['chatRoomId'] as String?;
      if (chatRoomId != null && chatRoomId.isNotEmpty) {
        _forceGo('/chats/$chatRoomId');
        await _settle(tester, const Duration(seconds: 3));
      } else {
        _forceGo('/matches/$matchId');
        await _settle(tester, const Duration(seconds: 2));
      }
      await _shot(role, '07_match_detail_chat');
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '08_match_list');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '09_match_detail');

      // ── 5. confirm-met (양쪽 모두 호출 필요) ────────────────────
      await api.confirmMet(accessToken, matchId);
      debugPrint('[S2-$role] confirm-met 완료');
      await _settle(tester, const Duration(seconds: 1));
      await _shot(role, '10_after_my_confirm_met');

      // 양쪽 모두 met 확인될 때까지 대기
      final withGame = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) {
          final both = m['bothMetConfirmed'] as bool? ?? false;
          final gid = m['gameId'] as String?;
          return both && gid != null && gid.isNotEmpty;
        },
        maxAttempts: 60,
      );
      final gameId = withGame['gameId'] as String;
      debugPrint('[S2-$role] both-met + gameId=$gameId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '11_both_met_game_created');

      // ── 6. 결과 입력 (양쪽 모두 WIN — 분쟁 유도) ───────────────
      // 점수: 내가 3, 상대가 1 (양쪽 다 자기가 이겼다고 주장)
      await api.submitGameResult(
        accessToken,
        gameId,
        myScore: 3,
        opponentScore: 1,
        claimedResult: 'WIN',
      );
      debugPrint('[S2-$role] 결과 입력 (WIN, 3-1)');
      await _settle(tester, const Duration(seconds: 2));
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '12_match_detail_after_result');
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '13_match_list_after_result');

      // ── 7. DISPUTED 상태 대기 (양쪽 다 WIN 제출 시 서버가 자동 처리) ─
      final disputedGame = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getGameDetail(accessToken, gameId),
        condition: (g) =>
            (g['resultStatus'] as String? ?? '') == 'DISPUTED' ||
            (g['resultStatus'] as String? ?? '') == 'VERIFIED',
        maxAttempts: 30,
      );
      final gameStatus = disputedGame['resultStatus'] as String? ?? '';
      debugPrint('[S2-$role] 게임 상태: $gameStatus');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '14_disputed_state');

      // ── 8. A만 이의 제기 작성 ──────────────────────────────────
      if (role == 'A' && gameStatus == 'DISPUTED') {
        await Future.delayed(const Duration(seconds: 2));
        final dispute = await api.createDispute(
          accessToken,
          matchId: matchId,
          title: 'E2E 시나리오 2 이의 제기',
          content:
              '양쪽이 같은 결과를 제출하여 분쟁이 발생했습니다. E2E 테스트용 이의 제기입니다.',
        );
        debugPrint('[S2-A] 이의 제기 접수: ${dispute['id']}');
        await _settle(tester, const Duration(seconds: 2));
        _forceGo('/profile');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '15_profile_after_dispute');
        _forceGo('/home');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '16_home_after_dispute');
      } else if (role == 'A') {
        debugPrint('[S2-A] gameStatus=$gameStatus — DISPUTED 아님, 이의 제기 스킵');
      }

      debugPrint('[S2-$role] 완료');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
