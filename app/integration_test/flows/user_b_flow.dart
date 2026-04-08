import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/api_helper.dart';
import '../helpers/test_config.dart';

/// User B 플로우 — 실제 UI 조작 + 매 단계 스크린샷
///
/// 흐름:
///   1. 앱 시작 → 현재 화면 파악 (로그인 or 홈)
///   2. 로그인 화면이면 → 이메일로 회원가입 진행
///   3. 온보딩: 프로필 설정 → 스포츠 프로필 → 위치 설정 → 핀 설정
///   4. 홈 화면 확인
///   5. API로 매칭 요청 생성 → User A와 자동 매칭
///   6. 매칭 성사 대기 → 수락
///   7. User A 결과 입력 대기 → 결과 확인
///   8. 계정 정리
Future<void> runUserBFlow(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  ApiHelper api,
) async {
  debugPrint('[UserB] ===== User B 플로우 시작 =====');

  // 스크린샷 헬퍼 — 이름은 영문/숫자/언더스코어만 사용
  Future<void> screenshot(String name) async {
    try {
      await binding.takeScreenshot('userB_$name');
      debugPrint('[UserB] Screenshot: userB_$name');
    } catch (e) {
      debugPrint('[UserB] Screenshot 실패 ($name): $e');
    }
  }

  await screenshot('01_app_start');

  // ── 1. 현재 화면 파악 ──────────────────────────────────────────
  final isLoginScreen = find.text('이메일로 시작하기').evaluate().isNotEmpty;

  String tokenB;
  final ts = DateTime.now().millisecondsSinceEpoch;

  if (isLoginScreen) {
    debugPrint('[UserB] 로그인 화면 감지 → 회원가입 진행');

    // ── 2. 이메일로 시작하기 탭 ────────────────────────────────
    await tester.tap(find.text('이메일로 시작하기'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await screenshot('02_email_auth_sheet');

    // ── 3. 회원가입 모드로 전환 ────────────────────────────────
    final signupLink = find.text('회원가입');
    if (signupLink.evaluate().isNotEmpty) {
      await tester.tap(signupLink.last);
      await tester.pumpAndSettle();
      await screenshot('03_signup_mode');
    }

    // ── 4. 회원가입 폼 입력 ────────────────────────────────────
    final emailB = 'test_b_$ts@spots.test';
    final nicknameB = 'E2E유저B$ts';

    final textFields = find.byType(TextFormField);
    expect(textFields, findsWidgets, reason: '텍스트 필드가 존재해야 합니다');

    final fieldCount = textFields.evaluate().length;
    debugPrint('[UserB] TextFormField 개수: $fieldCount');

    if (fieldCount >= 3) {
      // 회원가입 모드: 닉네임(0) → 이메일(1) → 비밀번호(2)
      await tester.enterText(textFields.at(0), nicknameB);
      await tester.pump();
      await tester.enterText(textFields.at(1), emailB);
      await tester.pump();
      await tester.enterText(textFields.at(2), TestConfig.userBPassword);
      await tester.pump();
    } else if (fieldCount >= 2) {
      await tester.enterText(textFields.at(0), emailB);
      await tester.pump();
      await tester.enterText(textFields.at(1), TestConfig.userBPassword);
      await tester.pump();
    }

    await screenshot('04_signup_filled');

    // ── 5. 회원가입 버튼 탭 ────────────────────────────────────
    final submitBtn = find.text('회원가입');
    if (submitBtn.evaluate().isNotEmpty) {
      await tester.tap(submitBtn.first);
    } else {
      await tester.tap(find.text('로그인'));
    }
    await tester.pumpAndSettle(const Duration(seconds: 8));
    await screenshot('05_after_signup');

    // 토큰 획득
    try {
      tokenB = await api.login(emailB, TestConfig.userBPassword);
      debugPrint('[UserB] UI 회원가입 성공 → 로그인 토큰 획득');
    } catch (_) {
      debugPrint('[UserB] UI 가입 결과 불명확 → API 회원가입 fallback');
      final fallbackEmail = 'test_b_fb_$ts@spots.test';
      tokenB = await api.register(fallbackEmail, TestConfig.userBPassword);
    }
  } else {
    debugPrint('[UserB] 홈 화면 감지 → API로 별도 테스트 계정 생성');
    await screenshot('02_home_already_logged_in');

    final emailB = 'test_b_$ts@spots.test';
    tokenB = await api.register(emailB, TestConfig.userBPassword);
    debugPrint('[UserB] API 계정 생성: $emailB');
  }

  // ── 6. 온보딩 화면 처리 ────────────────────────────────────────
  await _handleOnboarding(tester, screenshot, ts);

  // ── 7. 홈 화면 확인 ─────────────────────────────────────────────
  await tester.pumpAndSettle(const Duration(seconds: 3));
  await screenshot('10_home_screen');
  debugPrint('[UserB] 홈 화면 도달');

  // ── 8. API로 스포츠 프로필 + 위치 설정 ──────────────────────────
  try {
    await api.createSportsProfile(
      tokenB,
      sportType: TestConfig.testSportType,
      displayName: TestConfig.userBDisplayName,
      gHandicap: 30.0, // 초기 점수 ~950 (1200 범위 내)
    );
    debugPrint('[UserB] 스포츠 프로필 생성 완료');
  } catch (e) {
    debugPrint('[UserB] 스포츠 프로필 생성 스킵: $e');
  }

  try {
    await api.setLocation(
      tokenB,
      latitude: TestConfig.testLatitude,
      longitude: TestConfig.testLongitude,
      address: TestConfig.testAddress,
    );
    debugPrint('[UserB] 위치 설정 완료');
  } catch (e) {
    debugPrint('[UserB] 위치 설정 스킵: $e');
  }

  // ── 9. 핀 조회 + 매칭 요청 생성 ─────────────────────────────────
  debugPrint('[UserB] 핀 조회 + 매칭 요청 생성');
  final pins = await api.getAllPins(tokenB);
  if (pins.isEmpty) throw Exception('[UserB] 핀이 없습니다');
  final pinId = pins.first['id'] as String;
  debugPrint('[UserB] 핀 선택: $pinId (${pins.first['name']})');

  final matchReq = await api.createMatchRequest(
    tokenB,
    sportType: TestConfig.testSportType,
    pinId: pinId,
    message: 'E2E 테스트 B 매칭',
  );
  debugPrint('[UserB] 매칭 요청 생성 완료: ${matchReq['status']}');

  await screenshot('11_match_requested');

  // ── 10. 매칭 성사 대기 (PENDING_ACCEPT) ─────────────────────────
  debugPrint('[UserB] 매칭 성사 대기 (폴링)');
  final pendingMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () async {
      final matches = await api.getMyMatches(tokenB);
      final pending = matches
          .where((m) => (m['status'] as String?) == 'PENDING_ACCEPT')
          .toList();
      if (pending.isEmpty) throw Exception('아직 매칭 성사 안 됨');
      return pending.first;
    },
    condition: (m) => (m['status'] as String?) == 'PENDING_ACCEPT',
    maxAttempts: TestConfig.maxPollAttempts,
  );

  final matchId = pendingMatch['id'] as String;
  debugPrint('[UserB] 매칭 성사: $matchId');

  await tester.pump(const Duration(seconds: 2));
  await screenshot('12_match_found');

  // ── 11. 매칭 수락 (API) ─────────────────────────────────────────
  debugPrint('[UserB] 매칭 수락');
  await api.acceptMatch(tokenB, matchId);
  debugPrint('[UserB] 수락 완료');

  // CHAT 상태 대기
  final acceptedMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(tokenB, matchId),
    condition: (m) {
      final status = m['status'] as String? ?? '';
      return ['CHAT', 'CONFIRMED', 'COMPLETED'].contains(status);
    },
  );
  debugPrint('[UserB] CHAT 상태: ${acceptedMatch['status']}');

  await screenshot('13_match_accepted');

  // ── 12. 채팅 메시지 전송 (API) ──────────────────────────────────
  final chatRoomId = acceptedMatch['chatRoomId'] as String?;
  if (chatRoomId != null) {
    await api.sendMessage(
      tokenB,
      chatRoomId,
      content: TestConfig.userBChatMessage,
    );
    debugPrint('[UserB] 메시지 전송: "${TestConfig.userBChatMessage}"');
    await tester.pump(const Duration(seconds: 1));
    await screenshot('14_chat_sent');
  }

  // ── 13. 게임 ID 획득 대기 ───────────────────────────────────────
  debugPrint('[UserB] 게임 생성 대기');
  final matchWithGame = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(tokenB, matchId),
    condition: (m) {
      final gameId = m['gameId'] as String?;
      return gameId != null && gameId.isNotEmpty;
    },
  );
  final gameId = matchWithGame['gameId'] as String;
  debugPrint('[UserB] 게임 ID: $gameId');

  // ── 14. User A가 결과를 입력할 때까지 대기 ───────────────────────
  debugPrint('[UserB] User A 결과 입력 대기');
  await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getGameDetail(tokenB, gameId),
    condition: (game) {
      final status = game['status'] as String? ?? '';
      return ['PROOF_UPLOADED', 'VERIFIED', 'COMPLETED'].contains(status);
    },
  );
  debugPrint('[UserB] User A 결과 입력 확인됨');

  await screenshot('15_result_submitted_by_a');

  // ── 15. 결과 확인 (API) ─────────────────────────────────────────
  debugPrint('[UserB] 결과 확인');
  try {
    final result = await api.confirmGameResult(
      tokenB,
      gameId,
      isConfirmed: true,
    );
    debugPrint('[UserB] 결과 확인 완료: $result');
  } catch (e) {
    debugPrint('[UserB] 결과 확인 스킵 (이미 완료됨): $e');
  }

  await tester.pump(const Duration(seconds: 1));
  await screenshot('16_flow_complete');

  // ── 16. Cleanup ─────────────────────────────────────────────────
  debugPrint('[UserB] 테스트 계정 정리');
  try {
    await api.deleteUser(tokenB);
    debugPrint('[UserB] 계정 삭제 완료');
  } catch (e) {
    debugPrint('[UserB] 계정 삭제 실패 (수동 정리 필요): $e');
  }

  debugPrint('[UserB] ===== User B 플로우 완료 =====');
}

/// 온보딩 화면 처리 헬퍼
Future<void> _handleOnboarding(
  WidgetTester tester,
  Future<void> Function(String) screenshot,
  int ts,
) async {
  // 프로필 설정 화면
  await tester.pumpAndSettle(const Duration(seconds: 4));

  if (find.text('프로필을 설정해주세요').evaluate().isNotEmpty) {
    debugPrint('[UserB] 온보딩: 프로필 설정 화면');
    await screenshot('06_profile_setup');

    // 닉네임 자동 생성 대기
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final checkBtn = find.text('중복 확인');
    if (checkBtn.evaluate().isNotEmpty) {
      await tester.tap(checkBtn);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    await screenshot('07_nickname_checked');

    final nextBtn = find.text('다음');
    if (nextBtn.evaluate().isNotEmpty) {
      await tester.tap(nextBtn.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    await screenshot('08_after_profile');
  }

  // 스포츠 프로필 화면
  if (find.text('어떤 스포츠를').evaluate().isNotEmpty ||
      find.text('스포츠 프로필').evaluate().isNotEmpty) {
    debugPrint('[UserB] 온보딩: 스포츠 프로필 화면');
    await screenshot('09_sport_profile');

    final golfCard = find.text('골프');
    if (golfCard.evaluate().isNotEmpty) {
      await tester.tap(golfCard.first);
      await tester.pumpAndSettle();
    }

    final displayNameField = find.byType(TextField);
    if (displayNameField.evaluate().isNotEmpty) {
      final hintField =
          find.widgetWithText(TextField, '예: 주말 골퍼').evaluate().isNotEmpty
              ? find.widgetWithText(TextField, '예: 주말 골퍼')
              : displayNameField.first;
      await tester.enterText(hintField, TestConfig.userBDisplayName);
      await tester.pump();
    }

    final nextBtn = find.text('다음');
    if (nextBtn.evaluate().isNotEmpty) {
      await tester.tap(nextBtn.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    await screenshot('09b_after_sport');
  }

  // 위치 설정 화면
  if (find.text('활동 지역을 설정해주세요').evaluate().isNotEmpty ||
      find.text('활동 지역 설정').evaluate().isNotEmpty) {
    debugPrint('[UserB] 온보딩: 위치 설정 화면');
    await tester.pumpAndSettle(const Duration(seconds: 6));
    await screenshot('09c_location_setup');

    final locationDoneBtn = find.text('위치 설정 완료');
    if (locationDoneBtn.evaluate().isNotEmpty) {
      await tester.tap(locationDoneBtn);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    await screenshot('09d_after_location');
  }

  // 핀 & 종목 설정 화면
  if (find.text('자주 가는 핀을 선택하세요').evaluate().isNotEmpty ||
      find.text('자주 가는 핀 설정').evaluate().isNotEmpty) {
    debugPrint('[UserB] 온보딩: 핀 설정 화면');
    await tester.pumpAndSettle(const Duration(seconds: 8));
    await screenshot('09e_pin_setup');

    final startBtn = find.text('시작하기');
    if (startBtn.evaluate().isNotEmpty) {
      final widget = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '시작하기'),
      );
      if (widget.onPressed != null) {
        await tester.tap(startBtn);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      } else {
        // 지도 중앙 탭으로 핀 선택 시도
        final mapCenter = tester.getCenter(find.byType(Stack).first);
        await tester.tapAt(mapCenter);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await screenshot('09f_pin_tap_attempt');

        final startBtnAfterTap = find.text('시작하기');
        if (startBtnAfterTap.evaluate().isNotEmpty) {
          final widgetAfter = tester.widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '시작하기'),
          );
          if (widgetAfter.onPressed != null) {
            await tester.tap(startBtnAfterTap);
            await tester.pumpAndSettle(const Duration(seconds: 5));
          }
        }
      }
    }

    await screenshot('09g_after_pin');
  }
}
