import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spots/main.dart' as app;

import 'helpers/api_helper.dart';
import 'helpers/test_config.dart';
import 'flows/user_a_flow_ui.dart';
import 'flows/user_b_flow_ui.dart';

/// E2E 매칭 플로우 테스트 — 토큰 주입 방식
///
/// 전략:
///   1. API로 계정 생성 + 프로필 설정
///   2. SecureStorage에 토큰 주입 (자동 로그인)
///   3. 앱 실행
///   4. 이후 모든 동작은 UI 조작으로 진행
///
/// 실행 방법:
///   # User A (iOS 시뮬레이터 'match')
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/matching_e2e_test.dart \
///     --dart-define=TEST_USER_ROLE=A \
///     --dart-define=TEST_API_BASE_URL=http://127.0.0.1:3000/v1 \
///     -d match
///
///   # User B (iOS 시뮬레이터 'kids')
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/matching_e2e_test.dart \
///     --dart-define=TEST_USER_ROLE=B \
///     --dart-define=TEST_API_BASE_URL=http://127.0.0.1:3000/v1 \
///     -d kids
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiHelper();

  const role = String.fromEnvironment('TEST_USER_ROLE', defaultValue: 'A');

  testWidgets(
    '매칭 E2E — UI 조작 방식 — 역할: $role',
    (tester) async {
      final ts = DateTime.now().millisecondsSinceEpoch;

      // ── 1. API로 계정 생성 ──────────────────────────────────────────
      final email =
          'e2e_${role.toLowerCase()}_$ts@test.com';
      final regResult = await api.registerFull(email, 'test123456');
      final token = regResult['accessToken'] as String;
      final userId = (regResult['user'] as Map<String, dynamic>)['id'] as String;

      // ── 2. 프로필 설정 (API) ─────────────────────────────────────────
      final nickname = '테스트${role}_$ts';
      await api.updateProfile(token, nickname: nickname);

      await api.createSportsProfile(
        token,
        sportType: TestConfig.testSportType,
        displayName: '테스트골퍼$role',
        gHandicap: 30.0,
      );

      await api.setLocation(
        token,
        latitude: TestConfig.testLatitude,
        longitude: TestConfig.testLongitude,
        address: TestConfig.testAddress,
      );

      // ── 3. SecureStorage에 토큰 주입 ────────────────────────────────
      // 앱과 동일한 옵션으로 storage 인스턴스 생성
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

      await storage.deleteAll(); // 기존 토큰 초기화
      await storage.write(key: 'access_token', value: token);
      await storage.write(
        key: 'refresh_token',
        value: regResult['refreshToken'] as String,
      );
      await storage.write(key: 'user_id', value: userId);

      // ── 4. 앱 실행 (자동 로그인) ────────────────────────────────────
      unawaited(Future(() => app.main()));

      // 스플래시→홈 전환 대기 (pumpAndSettle 대신 반복 pump)
      bool reachedHome = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        // 바텀 네비의 '홈' 텍스트가 보이면 홈 도달
        if (find.text('홈').evaluate().isNotEmpty) {
          reachedHome = true;
          break;
        }
      }
      debugPrint('[E2E] 홈 도달: $reachedHome (role: $role)');
      await tester.pump(const Duration(seconds: 2));

      // ── 5. 역할별 UI 플로우 실행 ────────────────────────────────────
      if (role == 'A') {
        await runUserAFlowUI(
          tester,
          binding,
          api: api,
          token: token,
          userId: userId,
        );
      } else if (role == 'B') {
        await runUserBFlowUI(
          tester,
          binding,
          api: api,
          token: token,
          userId: userId,
        );
      } else {
        fail(
          'TEST_USER_ROLE 환경변수를 "A" 또는 "B"로 설정하세요.\n'
          '현재 값: "$role"\n'
          '예: --dart-define=TEST_USER_ROLE=A',
        );
      }

      // ── 6. Cleanup ───────────────────────────────────────────────────
      try {
        await api.deleteUser(token);
      } catch (e) {
        debugPrint('[E2E] 계정 삭제 실패 (수동 정리 필요): $e');
      }
    },
    timeout: const Timeout(TestConfig.testTimeout),
  );
}
