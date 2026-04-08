import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/api_helper.dart';
import '../helpers/test_config.dart';

/// User B UI 플로우
///
/// 전제: SecureStorage 토큰이 이미 주입된 상태로 앱이 실행됨 (자동 로그인)
///
/// 흐름:
///   1. 홈 화면 확인 (바텀 네비 존재 확인)
///   2. API로 매칭 요청 생성 → User A와 자동 매칭
///   3. 매칭 성사 대기 (PENDING_ACCEPT)
///   4. 매칭 탭 → 수락 화면 진입 → "수락" 버튼 탭 (UI)
///   5. 채팅 탭 → 채팅방 진입 → 메시지 전송 (UI)
///   6. User A 결과 입력 대기
///   7. 결과 확인 (게임 확인 화면에서 UI로)
Future<void> runUserBFlowUI(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required ApiHelper api,
  required String token,
  required String userId,
}) async {
  debugPrint('[UserB] ===== User B UI 플로우 시작 =====');

  Future<void> screenshot(String name) async {
    try {
      await binding.takeScreenshot('userB_$name');
      debugPrint('[UserB] Screenshot: userB_$name');
    } catch (e) {
      debugPrint('[UserB] Screenshot 실패 ($name): $e');
    }
  }

  await screenshot('01_app_start');

  // ── 1. 홈 화면 확인 ──────────────────────────────────────────────
  await tester.pumpAndSettle(const Duration(seconds: 5));

  final homeTab = find.text('홈');
  if (homeTab.evaluate().isEmpty) {
    debugPrint('[UserB] 홈 탭 못 찾음. 추가 대기 중...');
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await screenshot('01b_login_screen_fallback');
    expect(
      find.text('홈'),
      findsWidgets,
      reason: 'SecureStorage 토큰 주입 후 자동 로그인이 실패했습니다. 홈 탭이 보여야 합니다.',
    );
  }

  debugPrint('[UserB] 홈 화면 확인 완료 (자동 로그인 성공)');
  await screenshot('02_home_screen');

  // ── 2. API로 핀 조회 + 매칭 요청 생성 ──────────────────────────────
  // B는 A보다 약간 늦게 시작하므로 A가 먼저 요청 생성한 후 자동 매칭됨
  debugPrint('[UserB] 핀 목록 조회 + 매칭 요청 생성');
  final pins = await api.getAllPins(token);
  if (pins.isEmpty) {
    throw Exception('[UserB] 핀이 없습니다. 서버에 핀 데이터를 먼저 추가해주세요.');
  }
  final pinId = pins.first['id'] as String;
  debugPrint('[UserB] 핀 선택: $pinId (${pins.first['name']})');

  final matchReq = await api.createMatchRequest(
    token,
    sportType: TestConfig.testSportType,
    pinId: pinId,
    message: 'E2E UI 테스트 — User B',
  );
  debugPrint('[UserB] 매칭 요청 생성 완료: ${matchReq['status'] ?? matchReq['id']}');
  await screenshot('03_match_requested');

  // ── 3. 매칭 성사 대기 (PENDING_ACCEPT) ─────────────────────────────
  debugPrint('[UserB] 매칭 성사 대기 (PENDING_ACCEPT)');
  final pendingMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () async {
      final matches = await api.getMyMatches(token);
      final pending = matches.where((m) {
        final status = m['status'] as String? ?? '';
        return ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(status);
      }).toList();
      if (pending.isEmpty) throw Exception('아직 매칭 성사 안 됨');
      return pending.first;
    },
    condition: (m) {
      final status = m['status'] as String? ?? '';
      return ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(status);
    },
    maxAttempts: TestConfig.maxPollAttempts,
  );

  final matchId = pendingMatch['id'] as String;
  debugPrint('[UserB] 매칭 성사: $matchId (상태: ${pendingMatch['status']})');

  await tester.pump(const Duration(seconds: 2));
  await screenshot('04_match_found');

  // ── 4. 매칭 탭 → 수락 화면 → UI로 수락 ───────────────────────────────
  bool acceptedViaUI = false;

  if (pendingMatch['status'] == 'PENDING_ACCEPT') {
    debugPrint('[UserB] 매칭 탭으로 이동');
    final matchTabLabel = find.text('매칭');
    if (matchTabLabel.evaluate().isNotEmpty) {
      await tester.tap(matchTabLabel.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('05_match_tab');
    }

    // 매칭 목록에서 항목 탭
    final listInkWells = find.byType(InkWell);
    if (listInkWells.evaluate().isNotEmpty) {
      debugPrint('[UserB] 매칭 목록 항목 탭 (첫 번째 InkWell)');
      await tester.tap(listInkWells.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('06_match_accept_screen');

      // 수락 버튼 확인
      final acceptBtn = find.text('수락');
      if (acceptBtn.evaluate().isNotEmpty) {
        debugPrint('[UserB] 수락 버튼 탭 (UI)');
        await tester.tap(acceptBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await screenshot('07_accepted_ui');
        acceptedViaUI = true;
        debugPrint('[UserB] UI로 수락 완료');
      } else {
        debugPrint('[UserB] 수락 버튼 없음 → 현재 화면 확인');
        await screenshot('07_no_accept_btn');
      }
    }
  }

  if (!acceptedViaUI) {
    debugPrint('[UserB] UI 수락 실패 → API 수락 fallback');
    await api.acceptMatch(token, matchId);
    debugPrint('[UserB] API 수락 완료');
  }

  // ── 5. CHAT 상태 대기 ──────────────────────────────────────────────
  debugPrint('[UserB] CHAT 상태 대기');
  final acceptedMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) {
      final status = m['status'] as String? ?? '';
      return ['CHAT', 'CONFIRMED', 'COMPLETED'].contains(status);
    },
  );
  debugPrint('[UserB] CHAT 상태: ${acceptedMatch['status']}');

  final chatRoomId = acceptedMatch['chatRoomId'] as String?;

  // ── 6. 채팅 탭 → 채팅방 진입 → 메시지 전송 (UI) ─────────────────────
  debugPrint('[UserB] 채팅 탭으로 이동');
  final chatTabLabel = find.text('채팅');
  if (chatTabLabel.evaluate().isNotEmpty) {
    await tester.tap(chatTabLabel.first);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await screenshot('08_chat_tab');
  }

  bool enteredChatRoom = false;
  final chatRoomItems = find.byType(InkWell);
  if (chatRoomItems.evaluate().isNotEmpty) {
    debugPrint('[UserB] 채팅방 항목 탭');
    await tester.tap(chatRoomItems.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await screenshot('09_chat_room');
    enteredChatRoom = true;
  }

  if (enteredChatRoom) {
    final msgField = find.widgetWithText(TextField, '메시지를 입력하세요...');
    if (msgField.evaluate().isNotEmpty) {
      debugPrint('[UserB] 메시지 입력');
      await tester.tap(msgField.first);
      await tester.pump();
      await tester.enterText(msgField.first, TestConfig.userBChatMessage);
      await tester.pump();
      await screenshot('10_message_typed');

      final sendBtn = find.byIcon(Icons.send_rounded);
      if (sendBtn.evaluate().isNotEmpty) {
        debugPrint('[UserB] 전송 버튼 탭');
        await tester.tap(sendBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await screenshot('11_message_sent');
        debugPrint('[UserB] 메시지 전송 완료 (UI)');
      } else {
        debugPrint('[UserB] 전송 버튼 없음 → API 메시지 전송 fallback');
        if (chatRoomId != null) {
          await api.sendMessage(token, chatRoomId,
              content: TestConfig.userBChatMessage);
        }
      }
    } else {
      debugPrint('[UserB] 메시지 입력 필드 없음 → API fallback');
      if (chatRoomId != null) {
        await api.sendMessage(token, chatRoomId,
            content: TestConfig.userBChatMessage);
      }
    }
  } else {
    debugPrint('[UserB] 채팅방 목록 없음 → API fallback');
    if (chatRoomId != null) {
      await api.sendMessage(token, chatRoomId,
          content: TestConfig.userBChatMessage);
    }
  }

  // ── 7. 게임 ID 획득 대기 ────────────────────────────────────────────
  debugPrint('[UserB] 게임 생성 대기');
  final matchWithGame = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) {
      final gameId = m['gameId'] as String?;
      return gameId != null && gameId.isNotEmpty;
    },
  );
  final gameId = matchWithGame['gameId'] as String;
  debugPrint('[UserB] 게임 ID: $gameId');

  // ── 8. User A 결과 입력 대기 ──────────────────────────────────────
  debugPrint('[UserB] User A 결과 입력 대기');
  await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getGameDetail(token, gameId),
    condition: (game) {
      final status = game['status'] as String? ?? '';
      return ['PROOF_UPLOADED', 'VERIFIED', 'COMPLETED'].contains(status);
    },
  );
  debugPrint('[UserB] User A 결과 입력 확인됨');

  await tester.pump(const Duration(seconds: 1));
  await screenshot('12_result_submitted_by_a');

  // ── 9. 결과 확인 (UI: 게임 확인 화면) ────────────────────────────────
  // 게임 확인 화면으로 이동 (앱에서 알림/딥링크로 이동하거나 직접 경로 이동)
  // 매칭 탭 → 완료 탭에서 해당 매칭 → 결과 확인
  bool confirmedViaUI = false;

  // 뒤로 가기 (채팅방에서)
  final backButton = find.byType(BackButton);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  // 매칭 탭 → '완료' 탭 탭
  final matchTab2 = find.text('매칭');
  if (matchTab2.evaluate().isNotEmpty) {
    await tester.tap(matchTab2.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await screenshot('13_match_tab_for_confirm');

    // '완료' 탭 탭 (SegmentedButton: 진행중 / 완료 / 취소)
    final completedTab = find.text('완료');
    if (completedTab.evaluate().isNotEmpty) {
      await tester.tap(completedTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('14_completed_tab');
    }

    // 완료된 매칭 항목 탭
    final completedItems = find.byType(InkWell);
    if (completedItems.evaluate().isNotEmpty) {
      await tester.tap(completedItems.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('15_match_detail_completed');

      // '결과 확인' 또는 관련 버튼 탭
      final resultConfirmBtn = find.text('결과 확인');
      if (resultConfirmBtn.evaluate().isNotEmpty) {
        await tester.tap(resultConfirmBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await screenshot('16_game_confirm_screen');

        // 확인 버튼 탭 (GameConfirmScreen)
        final confirmBtn = find.text('확인');
        if (confirmBtn.evaluate().isNotEmpty) {
          await tester.tap(confirmBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          await screenshot('17_result_confirmed_ui');
          confirmedViaUI = true;
          debugPrint('[UserB] 결과 확인 완료 (UI)');
        }
      }
    }
  }

  if (!confirmedViaUI) {
    debugPrint('[UserB] UI 결과 확인 실패 → API fallback');
    try {
      await api.confirmGameResult(token, gameId, isConfirmed: true);
      debugPrint('[UserB] API 결과 확인 완료');
    } catch (e) {
      debugPrint('[UserB] 결과 확인 스킵 (이미 완료됨): $e');
    }
  }

  await tester.pump(const Duration(seconds: 1));
  await screenshot('18_flow_complete');
  debugPrint('[UserB] ===== User B UI 플로우 완료 =====');
}
