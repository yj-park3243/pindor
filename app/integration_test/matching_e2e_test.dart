import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
/// orchestrator(run_matching_test.sh)가 사전 준비:
///   1. API로 유저 등록 + is_verified=true + 프로필/스포츠/위치 세팅
///   2. 발급된 토큰과 userId를 --dart-define으로 주입
///
/// 테스트는 다음만 수행:
///   1. SecureStorage에 주입된 토큰 저장
///   2. 앱 실행 (자동 로그인)
///   3. 역할별 UI 시나리오 (매칭 요청 → 수락 → 결과 → 점수 반영)
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiHelper();

  const role = String.fromEnvironment('TEST_USER_ROLE', defaultValue: 'A');
  const accessToken = String.fromEnvironment('TEST_ACCESS_TOKEN');
  const refreshToken = String.fromEnvironment('TEST_REFRESH_TOKEN');
  const userId = String.fromEnvironment('TEST_USER_ID');

  testWidgets(
    '매칭 E2E — UI 조작 방식 — 역할: $role',
    (tester) async {
      expect(
        accessToken.isNotEmpty,
        true,
        reason:
            'TEST_ACCESS_TOKEN이 비어있습니다. run_matching_test.sh로 실행하거나 --dart-define=TEST_ACCESS_TOKEN=... 을 지정하세요.',
      );
      expect(userId.isNotEmpty, true,
          reason: 'TEST_USER_ID가 비어있습니다.');

      debugPrint('[E2E] role=$role userId=$userId');

      // ── 1. SecureStorage에 토큰 주입 ────────────────────────────────
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

      // ── 2. 앱 실행 (자동 로그인) ────────────────────────────────────
      unawaited(Future(() => app.main()));

      bool reachedHome = false;
      for (var i = 0; i < 60; i++) {
        // pumpAndSettle은 OverlayEntry/애니메이션 무한루프에서 hang될 수 있어
        // timeout 짧게 잡고 catch
        try {
          await tester.pumpAndSettle(const Duration(milliseconds: 800));
        } catch (_) {
          await tester.pump(const Duration(seconds: 1));
        }

        // "허용" 시스템 다이얼로그 자동 dismiss (알림/위치 권한)
        final allow = find.text('허용');
        if (allow.evaluate().isNotEmpty) {
          try {
            await tester.tap(allow.first, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 500));
          } catch (_) {}
        }

        if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty) {
          reachedHome = true;
          debugPrint('[E2E] 홈 도달 (${i + 1}초): role=$role');
          break;
        }

        // 디버깅: 5초마다 현재 위젯 트리 상태 일부 로그
        if (i % 5 == 4) {
          final texts = find
              .byType(Text)
              .evaluate()
              .take(8)
              .map((e) => (e.widget as Text).data ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          debugPrint('[E2E] ${i + 1}초 — 현재 화면 텍스트 일부: $texts');
        }
      }
      debugPrint('[E2E] 홈 도달: $reachedHome (role: $role)');
      await tester.pump(const Duration(seconds: 2));

      // ── 3. 역할별 UI 플로우 실행 ────────────────────────────────────
      if (role == 'A') {
        await runUserAFlowUI(
          tester,
          binding,
          api: api,
          token: accessToken,
          userId: userId,
        );
      } else if (role == 'B') {
        await runUserBFlowUI(
          tester,
          binding,
          api: api,
          token: accessToken,
          userId: userId,
        );
      } else {
        fail('TEST_USER_ROLE 환경변수는 "A" 또는 "B"여야 합니다. 현재: "$role"');
      }
    },
    timeout: const Timeout(TestConfig.testTimeout),
  );
}
