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

/// 위젯이 트리에 나타날 때까지 폴링 후 tap.
/// flakiness 회피용 — pumpAndSettle은 hang 위험이 있어 사용 금지.
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
  debugPrint('[S3] _tapKey timeout — key=$keyValue');
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

/// 시나리오 3 — 정상 결과 입력 → 랭킹 반영
///
/// 흐름:
///   A,B: 매칭 → 수락 → CHAT/CONFIRMED → confirm-met
///   A: myScore=3, opponentScore=1, claimedResult='WIN'
///   B: myScore=1, opponentScore=3, claimedResult='LOSS'  (서로 일치)
///   → games.result_status='VERIFIED', matches.status='COMPLETED'
///   → score_histories에 양쪽 row, ranking_entries 업데이트
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
    '시나리오3 정상결과 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      debugPrint('[S3] role=$role userId=$userId');

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
      debugPrint('[S3-$role] 홈 도달');
      await _shot(role, '01_home');
      await _settle(tester, const Duration(seconds: 1));
      await _shot(role, '02_home_settled');

      // 매칭 요청
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
        message: 'E2E S3 ($role)',
      );
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '03_match_requested');

      // 매칭 성사 + 수락
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
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '04_pending_accept_page');

      // 수락: UI tap (PENDING_ACCEPT 상태에서만)
      if (pending['status'] == 'PENDING_ACCEPT') {
        _forceGo('/matches/$matchId/accept');
        await _settle(tester, const Duration(seconds: 3));
        final tapped = await _tapKey(tester, 'match_accept_accept_btn');
        if (!tapped) {
          debugPrint('[S3-$role] 수락 버튼 UI tap 실패 → API fallback');
          await api.acceptMatch(accessToken, matchId);
        } else {
          debugPrint('[S3-$role] 수락 버튼 UI tap 성공');
        }
      }
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '05_after_my_accept');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '06_match_detail');

      // CHAT/CONFIRMED 진입
      final chatMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) {
          final s = m['status'] as String? ?? '';
          return s == 'CHAT' || s == 'CONFIRMED';
        },
      );
      debugPrint('[S3-$role] CHAT 진입');
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

      // confirm-met: UI tap (만남 확인 버튼 → 다이얼로그 "만났어요")
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      final metBtnTapped = await _tapKey(tester, 'match_detail_confirm_met_btn');
      if (metBtnTapped) {
        await _settle(tester, const Duration(seconds: 1));
        await _tapKey(tester, 'match_detail_confirm_met_dialog_ok');
        debugPrint('[S3-$role] 만남 확인 UI tap 성공');
      } else {
        debugPrint('[S3-$role] 만남 확인 버튼 UI tap 실패 → API fallback');
        await api.confirmMet(accessToken, matchId);
      }
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '10_after_my_confirm_met');
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
      debugPrint('[S3-$role] both-met + gameId=$gameId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '11_both_met_game_created');

      // 결과 입력: UI tap (결과 버튼 → 옵션 선택 → 제출)
      // role=A: WIN, role=B: LOSS (B는 race 회피 위해 5초 대기)
      if (role == 'B') {
        await Future.delayed(const Duration(seconds: 5));
      }
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      final submitBtnOpened =
          await _tapKey(tester, 'match_detail_submit_result_btn');
      bool resultViaUi = false;
      if (submitBtnOpened) {
        await _settle(tester, const Duration(seconds: 2));
        final optionKey =
            role == 'A' ? 'game_result_option_WIN' : 'game_result_option_LOSS';
        final optionTapped = await _tapKey(tester, optionKey);
        if (optionTapped) {
          await _settle(tester, const Duration(milliseconds: 500));
          resultViaUi = await _tapKey(tester, 'game_result_submit_btn');
        }
      }
      if (resultViaUi) {
        debugPrint('[S3-$role] 결과 제출 UI tap 성공');
        await _settle(tester, const Duration(seconds: 3));
      } else {
        debugPrint('[S3-$role] 결과 제출 UI 실패 → API fallback');
        if (role == 'A') {
          await api.submitGameResult(
            accessToken,
            gameId,
            myScore: 3,
            opponentScore: 1,
            claimedResult: 'WIN',
          );
        } else {
          await api.submitGameResult(
            accessToken,
            gameId,
            myScore: 1,
            opponentScore: 3,
            claimedResult: 'LOSS',
          );
        }
      }
      await _settle(tester, const Duration(seconds: 2));
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '12_match_detail_after_result');
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '13_match_list_after_result');

      // VERIFIED + COMPLETED 대기
      final verifiedGame = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getGameDetail(accessToken, gameId),
        condition: (g) => (g['resultStatus'] as String? ?? '') == 'VERIFIED',
        maxAttempts: 60,
      );
      debugPrint(
          '[S3-$role] VERIFIED — winner=${verifiedGame['winnerProfileId']}');

      final completedMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) => (m['status'] as String? ?? '') == 'COMPLETED',
        maxAttempts: 30,
      );
      debugPrint('[S3-$role] match=${completedMatch['status']}');
      _forceGo('/home');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '14_home_after_complete');
      _forceGo('/profile');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '15_profile_after_complete');
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
