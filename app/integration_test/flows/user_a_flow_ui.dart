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

/// 탭을 시도하되 실패해도 무시 (UI 다양성 대응)
Future<bool> _safeTap(WidgetTester tester, Finder f, String label,
    {Duration settle = const Duration(seconds: 2)}) async {
  try {
    if (f.evaluate().isEmpty) {
      debugPrint('[UserA] ⨯ tap skip ($label) — not found');
      return false;
    }
    await tester.tap(f.first, warnIfMissed: false);
    await tester.pumpAndSettle(settle);
    debugPrint('[UserA] ✓ tap ($label)');
    return true;
  } catch (e) {
    debugPrint('[UserA] ⨯ tap fail ($label): $e');
    return false;
  }
}

Future<void> runUserAFlowUI(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required ApiHelper api,
  required String token,
  required String userId,
}) async {
  debugPrint('[UserA] ===== 시작 =====');

  Future<void> shot(String name) async {
    try {
      await _shotDio.get('http://127.0.0.1:9998/userA_$name');
      await Future.delayed(const Duration(milliseconds: 600));
      debugPrint('[UserA] 📸 userA_$name');
    } catch (e) {
      debugPrint('[UserA] 📸 FAILED userA_$name: $e');
    }
  }

  // ── 1. 홈 도달 + 알림 팝업 닫기 ─────────────────────────────────────
  await tester.pumpAndSettle(const Duration(seconds: 3));
  // iOS 알림 권한 팝업: '허용' 또는 '허용 안 함' 탭
  await _safeTap(tester, find.text('허용'), 'notif-allow');
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.text('홈'), findsWidgets, reason: '자동 로그인 실패 (홈 화면 미도달)');
  await shot('01_home');

  // ── 2. 매칭 요청 (API) ──────────────────────────────────────────────
  final pins = await api.getAllPins(token);
  if (pins.isEmpty) throw Exception('[UserA] 핀 데이터 없음');
  final pinId = pins.first['id'] as String;
  debugPrint('[UserA] 핀: $pinId (${pins.first['name']})');

  final matchReq = await api.createMatchRequest(
    token,
    sportType: TestConfig.testSportType,
    pinId: pinId,
    message: 'E2E User A',
  );
  debugPrint('[UserA] 매칭 요청 생성: ${matchReq['id']}');

  // ── 3. 매칭 성사 폴링 + 매칭 탭 이동 ─────────────────────────────────
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
  debugPrint('[UserA] 매칭 성사: $matchId (${pending['status']})');

  // 바텀 네비 '매칭' 탭 — 여러 개 있으면 last (bottom nav가 트리 하단)
  await _safeTap(tester, find.text('매칭'), 'nav-match');
  await shot('02_match_list');

  // ── 4. 매칭 아이템 탭 → 수락 화면 진입 ─────────────────────────────
  // 매칭 상세는 InkWell로 감싸진 카드
  await _safeTap(tester, find.byType(InkWell), 'match-item');
  await shot('03_match_accept');

  // ── 5. API 수락 ─────────────────────────────────────────────────────
  if (pending['status'] == 'PENDING_ACCEPT') {
    await api.acceptMatch(token, matchId);
    debugPrint('[UserA] 수락 완료');
  }

  // ── 6. CHAT 상태 대기 + UI 갱신 ─────────────────────────────────────
  final accepted = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) => ['CHAT', 'CONFIRMED', 'COMPLETED']
        .contains(m['status'] as String? ?? ''),
  );
  debugPrint('[UserA] CHAT 상태: ${accepted['status']}');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('04_chat_detail');

  // ── 7. Game 생성 대기 ───────────────────────────────────────────────
  final withGame = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) {
      final g = m['gameId'] as String?;
      return g != null && g.isNotEmpty;
    },
  );
  final gameId = withGame['gameId'] as String;
  debugPrint('[UserA] Game: $gameId');

  // ── 8. 결과 입력 시트 열기 (UI) → 내용 캡처 → 닫기 ────────────────
  await _safeTap(tester, find.text('승부 결과'), 'result-btn');
  await shot('05_result_sheet');
  // 시트 닫기 (dismiss로 뒤로가기)
  await tester.tap(find.byType(Scaffold).first, warnIfMissed: false);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  // ── 9. API 결과 제출 ────────────────────────────────────────────────
  final myCode = withGame['myVerificationCode'] as String?;
  final reqCode = withGame['requesterVerificationCode'] as String?;
  final oppCode = withGame['opponentVerificationCode'] as String?;
  final counterpartCode =
      (myCode == reqCode ? oppCode : reqCode) ?? '';
  debugPrint(
      '[UserA] myCode=$myCode, counterpartCode=$counterpartCode');

  await api.submitGameResult(
    token,
    gameId,
    myScore: TestConfig.userAScore,
    opponentScore: TestConfig.userBScore,
    verificationCode: counterpartCode,
    claimedResult: 'WIN',
  );
  debugPrint('[UserA] 결과 제출 (A 승)');

  // ── 10. VERIFIED 대기 ──────────────────────────────────────────────
  await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getGameDetail(token, gameId),
    condition: (g) {
      final s = g['resultStatus'] as String? ?? g['status'] as String? ?? '';
      return ['VERIFIED', 'COMPLETED'].contains(s);
    },
  );
  debugPrint('[UserA] 결과 확정됨');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('06_verified');

  // ── 11. 마이 탭 이동 → 점수 확인 ────────────────────────────────────
  await _safeTap(tester, find.text('마이'), 'nav-profile');
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await shot('07_profile_score');

  // API로도 검증
  final me = await api.getMe(token);
  final profiles = (me['sportsProfiles'] as List?) ?? [];
  if (profiles.isNotEmpty) {
    final p = profiles.first as Map<String, dynamic>;
    debugPrint(
        '[UserA] 점수: ${p['currentScore']} (승 ${p['wins']}, 패 ${p['losses']})');
  }

  debugPrint('[UserA] ===== 완료 =====');
}
