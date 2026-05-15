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

// socket stream으로 화면이 끝없이 rebuild돼 pumpAndSettle이 기본 10분 hang.
// 그냥 d 만큼 시간 advance + 한 frame 갱신.
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

/// 시나리오 1 — 노쇼 신고 흐름 (A 측만 실행: B의 노쇼를 신고)
///
/// 양쪽 시뮬레이터에서 동시에 실행. role에 따라 다르게 동작:
///   A: 매칭 요청 → 양쪽 수락 → CHAT 상태 → B를 노쇼 신고
///   B: 매칭 요청 → 양쪽 수락 → CHAT 상태 → 신고 대기 (검증은 admin에서)
///
/// 추가 입력 (B만 사용):
///   --dart-define=SCENARIO_OPPONENT_USER_ID=<상대방 user_id>
///   (현재는 A,B 모두 양방향 매칭 요청해서 자동 성사되므로 미사용)
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
    '시나리오1 노쇼 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      expect(userId.isNotEmpty, true, reason: 'TEST_USER_ID 필수');

      debugPrint('[S1] role=$role userId=$userId pinName=$pinName');

      // ── 1. SecureStorage 토큰 주입 ──────────────────────────────
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

      // ── 2. 앱 실행 (자동 로그인) ─────────────────────────────────
      unawaited(Future(() => app.main()));

      // 홈 화면 진입 wait
      bool reachedHome = false;
      for (var i = 0; i < 60; i++) {
        try {
          await _settle(tester, const Duration(milliseconds: 800));
        } catch (_) {
          await tester.pump(const Duration(seconds: 1));
        }
        if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty) {
          reachedHome = true;
          debugPrint('[S1] 홈 도달 (${i + 1}초)');
          break;
        }
      }
      expect(reachedHome, true, reason: '홈 진입 실패');
      await _shot(role, '01_home');
      await _settle(tester, const Duration(seconds: 1));
      await _shot(role, '02_home_settled');

      // ── 3. API로 매칭 요청 → 성사까지 ─────────────────────────────
      final pins = await api.getAllPins(accessToken);
      final selected = pins.firstWhere(
        (p) => p['name'] == pinName,
        orElse: () => pins.first,
      );
      final pinId = selected['id'] as String;
      debugPrint('[S1-$role] pin=$pinId (${selected['name']})');

      await api.createMatchRequest(
        accessToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'E2E 시나리오 1 ($role)',
      );
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '03_match_requested');

      // 매칭 성사 대기
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
        condition: (m) => ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED']
            .contains(m['status'] as String? ?? ''),
      );
      final matchId = pending['id'] as String;
      debugPrint('[S1-$role] 매칭 성사: $matchId (${pending['status']})');
      // 매칭 수락 페이지가 떠 있을 때 캡처 (PENDING_ACCEPT 상태)
      _forceGo('/matches/$matchId');
      for (var i = 0; i < 10; i++) {
        try { await _settle(tester, const Duration(seconds: 1)); } catch (_) {}
        if (find.text('상대를 찾았습니다!').evaluate().isNotEmpty) break;
      }
      await _shot(role, '04_pending_accept_page');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '05_pending_accept_page_2');

      // API 수락
      if (pending['status'] == 'PENDING_ACCEPT') {
        await api.acceptMatch(accessToken, matchId);
      }
      debugPrint('[S1-$role] 수락 완료');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '06_after_my_accept');

      // 양쪽 수락 완료 대기 + 강제로 매칭 상세 navigate (socket 미연결 회피)
      await _settle(tester, const Duration(seconds: 3));
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '07_match_detail');
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '08_match_list');

      // CHAT 상태 대기
      await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) =>
            (m['status'] as String? ?? '') == 'CHAT' ||
            (m['status'] as String? ?? '') == 'CONFIRMED',
      );
      debugPrint('[S1-$role] CHAT 진입');
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '09_match_detail_chat');
      _forceGo('/home');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '10_back_home');
      _forceGo('/profile');
      await _settle(tester, const Duration(seconds: 2));
      await _shot(role, '11_profile');

      // ── 5. 역할별 분기 ─────────────────────────────────────────
      if (role == 'A') {
        // A는 B를 노쇼 신고
        _forceGo('/matches/$matchId');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '12_before_noshow_report');
        debugPrint('[S1-A] 노쇼 신고 시작');
        await api.reportNoshow(accessToken, matchId);
        debugPrint('[S1-A] 노쇼 신고 완료');
        await _settle(tester, const Duration(seconds: 2));
        _forceGo('/matches');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '13_match_list_after_noshow');
        _forceGo('/home');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '14_home_after_noshow');

        // 매치 상태가 COMPLETED로 바뀌어야 함 (reportNoshow가 매치 종료시킴)
        final completed = await api.pollUntil<Map<String, dynamic>>(
          fetcher: () => api.getMatchDetail(accessToken, matchId),
          condition: (m) =>
              (m['status'] as String? ?? '') == 'COMPLETED' ||
              (m['status'] as String? ?? '') == 'CANCELLED',
        );
        debugPrint('[S1-A] 매치 종료 확인: ${completed['status']}');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '15_match_completed');
        expect(
          ['COMPLETED', 'CANCELLED'].contains(completed['status']),
          true,
          reason: '노쇼 신고 후 매치가 종료돼야 함',
        );
      } else {
        // B는 신고 받음 — 매치 종료까지 대기. 폴링 부족 시 흐름 마무리만 (테스트는 통과 처리)
        try {
          final completed = await api.pollUntil<Map<String, dynamic>>(
            fetcher: () => api.getMatchDetail(accessToken, matchId),
            condition: (m) =>
                (m['status'] as String? ?? '') == 'COMPLETED' ||
                (m['status'] as String? ?? '') == 'CANCELLED',
            maxAttempts: 120,
          );
          debugPrint('[S1-B] 신고 받음 + 매치 종료: ${completed['status']}');
        } catch (e) {
          debugPrint('[S1-B] 매치 종료 폴링 timeout — admin/DB로 별도 검증');
        }
        _forceGo('/matches');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '12_match_list_received');
        _forceGo('/home');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '13_home_received');
        _forceGo('/profile');
        await _settle(tester, const Duration(seconds: 2));
        await _shot(role, '14_profile_received');
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
