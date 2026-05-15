import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/api_helper.dart';
import '../helpers/test_config.dart';

final Dio _shotDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 2),
  receiveTimeout: const Duration(seconds: 3),
));

Future<bool> _safeTap(WidgetTester tester, Finder f, String label,
    {Duration settle = const Duration(seconds: 2)}) async {
  try {
    if (f.evaluate().isEmpty) {
      debugPrint('[UserB] ⨯ tap skip ($label) — not found');
      return false;
    }
    await tester.tap(f.first, warnIfMissed: false);
    await tester.pumpAndSettle(settle);
    debugPrint('[UserB] ✓ tap ($label)');
    return true;
  } catch (e) {
    debugPrint('[UserB] ⨯ tap fail ($label): $e');
    return false;
  }
}

Future<void> runUserBFlowUI(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required ApiHelper api,
  required String token,
  required String userId,
}) async {
  debugPrint('[UserB] ===== 시작 =====');

  Future<void> shot(String name) async {
    try {
      await _shotDio.get('http://127.0.0.1:9998/userB_$name');
      await Future.delayed(const Duration(milliseconds: 600));
      debugPrint('[UserB] 📸 userB_$name');
    } catch (e) {
      debugPrint('[UserB] 📸 FAILED userB_$name: $e');
    }
  }

  // 1. 홈 + 알림/위치 권한 + 강제업데이트 팝업 처리
  for (var i = 0; i < 8; i++) {
    try {
      await tester.pumpAndSettle(const Duration(seconds: 1));
    } catch (_) {
      await tester.pump(const Duration(seconds: 1));
    }
    // 자주 등장하는 권한/공지 버튼 dismiss
    for (final label in ['허용', '확인', '나중에', '닫기']) {
      final f = find.text(label);
      if (f.evaluate().isNotEmpty) {
        try {
          await tester.tap(f.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
        } catch (_) {}
      }
    }
    if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty) break;
  }
  expect(find.text('오늘 대결 나가고 싶다!'), findsWidgets,
      reason: '자동 로그인 실패');
  await shot('01_home');

  // 2. 매칭 요청
  final pins = await api.getAllPins(token);
  if (pins.isEmpty) throw Exception('[UserB] 핀 데이터 없음');
  final selected = pins.firstWhere(
    (p) => p['name'] == TestConfig.testPinName,
    orElse: () => pins.first,
  );
  final pinId = selected['id'] as String;
  debugPrint('[UserB] 핀: $pinId (${selected['name']})');

  final matchReq = await api.createMatchRequest(
    token,
    sportType: TestConfig.testSportType,
    pinId: pinId,
    message: 'E2E User B',
  );
  debugPrint('[UserB] 매칭 요청 생성: ${matchReq['id'] ?? matchReq['status']}');

  // 3. 매칭 성사 + 매칭 탭
  final pending = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () async {
      final ms = await api.getMyMatches(token);
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
  debugPrint('[UserB] 매칭 성사: $matchId (${pending['status']})');
  await _safeTap(tester, find.text('매칭'), 'nav-match');
  await shot('02_match_list');

  // 4. API 수락 (UI 거절 시트가 뜨지 않도록 직접 API)
  if (pending['status'] == 'PENDING_ACCEPT') {
    await api.acceptMatch(token, matchId);
    debugPrint('[UserB] 수락 완료');
  }
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('03_match_accept');

  // 6. CHAT 대기
  final accepted = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) => ['CHAT', 'CONFIRMED', 'COMPLETED']
        .contains(m['status'] as String? ?? ''),
  );
  debugPrint('[UserB] CHAT: ${accepted['status']}');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('04_chat_detail');

  // 7. Game 생성 대기
  final withGame = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) {
      final g = m['gameId'] as String?;
      return g != null && g.isNotEmpty;
    },
  );
  final gameId = withGame['gameId'] as String;
  debugPrint('[UserB] Game: $gameId');

  // 8. 결과 입력 시트 (UI) → 캡처 → 닫기
  await _safeTap(tester, find.text('승부 결과'), 'result-btn');
  await shot('05_result_sheet');
  await tester.tap(find.byType(Scaffold).first, warnIfMissed: false);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  // 9. API 결과 제출 (B 패)
  final myCode = withGame['myVerificationCode'] as String?;
  final reqCode = withGame['requesterVerificationCode'] as String?;
  final oppCode = withGame['opponentVerificationCode'] as String?;
  final counterpartCode =
      (myCode == reqCode ? oppCode : reqCode) ?? '';
  debugPrint('[UserB] myCode=$myCode, counterpartCode=$counterpartCode');

  try {
    await api.submitGameResult(
      token,
      gameId,
      myScore: TestConfig.userBScore,
      opponentScore: TestConfig.userAScore,
      verificationCode: counterpartCode,
      claimedResult: 'LOSS',
    );
    debugPrint('[UserB] 결과 제출 (B 패)');
  } catch (e) {
    debugPrint('[UserB] 결과 제출 에러 (이미 제출 또는 순서 문제): $e');
  }

  // 10. VERIFIED 대기
  final finalGame = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getGameDetail(token, gameId),
    condition: (g) {
      final s = g['resultStatus'] as String? ?? g['status'] as String? ?? '';
      return ['VERIFIED', 'COMPLETED'].contains(s);
    },
  );
  debugPrint('[UserB] 최종 상태: ${finalGame['resultStatus'] ?? finalGame['status']}');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('06_verified');

  // 11. 마이 탭 이동
  await _safeTap(tester, find.text('마이'), 'nav-profile');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('07_profile_score');

  final me = await api.getMe(token);
  final profiles = (me['sportsProfiles'] as List?) ?? [];
  if (profiles.isNotEmpty) {
    final p = profiles.first as Map<String, dynamic>;
    debugPrint(
        '[UserB] 점수: ${p['currentScore']} (승 ${p['wins']}, 패 ${p['losses']})');
  }

  debugPrint('[UserB] ===== 완료 =====');
}
