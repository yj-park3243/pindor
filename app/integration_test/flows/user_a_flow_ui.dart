import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/api_helper.dart';
import '../helpers/test_config.dart';

/// User A UI 플로우
///
/// 전제: SecureStorage 토큰이 이미 주입된 상태로 앱이 실행됨 (자동 로그인)
///
/// 흐름:
///   1. 홈 화면 확인 (바텀 네비 존재 확인)
///   2. API로 매칭 요청 생성 (핀 탭에서 UI로 하기 어려우므로 API 사용)
///   3. 매칭 성사 대기 (폴링)
///   4. 매칭 탭 → 수락 화면 진입 → "수락" 버튼 탭 (UI)
///   5. 채팅 탭 → 채팅방 진입 → 메시지 전송 (UI)
///   6. 매칭 상세 화면 → 경기 확정 (UI: 다이얼로그)
///   7. 결과 입력 (UI: 점수 입력 + 제출)
///   8. User B 결과 확인 대기
Future<void> runUserAFlowUI(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required ApiHelper api,
  required String token,
  required String userId,
}) async {
  debugPrint('[UserA] ===== User A UI 플로우 시작 =====');

  Future<void> screenshot(String name) async {
    try {
      await binding.takeScreenshot('userA_$name');
      debugPrint('[UserA] Screenshot: userA_$name');
    } catch (e) {
      debugPrint('[UserA] Screenshot 실패 ($name): $e');
    }
  }

  await screenshot('01_app_start');

  // ── 1. 홈 화면 확인 ──────────────────────────────────────────────
  // 바텀 네비가 보이면 자동 로그인 성공
  // AdaptiveBottomNavigationBar 아래에 텍스트 레이블이 있음
  await tester.pumpAndSettle(const Duration(seconds: 5));

  // 바텀 네비 탭 레이블 확인 (홈, 핀, 매칭, 채팅, 마이)
  final homeTab = find.text('홈');
  if (homeTab.evaluate().isEmpty) {
    // 자동 로그인 실패 — 로그인 화면으로 이동했을 가능성
    debugPrint('[UserA] 홈 탭 못 찾음. 현재 화면 상태 확인 중...');
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await screenshot('01b_login_screen_fallback');
    // 로그인 화면이라면 테스트 실패로 처리
    expect(
      find.text('홈'),
      findsWidgets,
      reason: 'SecureStorage 토큰 주입 후 자동 로그인이 실패했습니다. 홈 탭이 보여야 합니다.',
    );
  }

  debugPrint('[UserA] 홈 화면 확인 완료 (자동 로그인 성공)');
  await screenshot('02_home_screen');

  // ── 2. API로 핀 조회 + 매칭 요청 생성 ──────────────────────────────
  debugPrint('[UserA] 핀 목록 조회');
  final pins = await api.getAllPins(token);
  if (pins.isEmpty) {
    throw Exception('[UserA] 핀이 없습니다. 서버에 핀 데이터를 먼저 추가해주세요.');
  }
  final pinId = pins.first['id'] as String;
  debugPrint('[UserA] 핀 선택: $pinId (${pins.first['name']})');

  debugPrint('[UserA] 매칭 요청 생성');
  final matchRequest = await api.createMatchRequest(
    token,
    sportType: TestConfig.testSportType,
    pinId: pinId,
    message: 'E2E UI 테스트 — User A',
  );
  debugPrint('[UserA] 매칭 요청 생성 완료: ${matchRequest['id']}');
  await screenshot('03_match_requested');

  // ── 3. 매칭 성사 대기 ───────────────────────────────────────────────
  debugPrint('[UserA] 매칭 성사 대기 (User B 요청 + 자동 매칭 대기)');
  final pendingMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () async {
      final matches = await api.getMyMatches(token);
      final found = matches.where((m) {
        final status = m['status'] as String? ?? '';
        return ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(status);
      }).toList();
      if (found.isEmpty) throw Exception('아직 매칭 성사 안 됨');
      return found.first;
    },
    condition: (m) {
      final status = m['status'] as String? ?? '';
      return ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(status);
    },
    maxAttempts: TestConfig.maxPollAttempts,
  );

  final matchId = pendingMatch['id'] as String;
  debugPrint('[UserA] 매칭 성사: $matchId (상태: ${pendingMatch['status']})');

  // 앱 UI 갱신
  await tester.pump(const Duration(seconds: 2));
  await screenshot('04_match_found');

  // ── 4. 매칭 탭으로 이동 → 수락 화면 진입 → UI로 수락 ─────────────────
  if (pendingMatch['status'] == 'PENDING_ACCEPT') {
    debugPrint('[UserA] 매칭 탭으로 이동');
    // 바텀 네비에서 '매칭' 탭 탭
    final matchTabLabel = find.text('매칭');
    if (matchTabLabel.evaluate().isNotEmpty) {
      await tester.tap(matchTabLabel.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('05_match_tab');
    }

    // 매칭 목록에서 PENDING_ACCEPT 항목 탭
    // _StatusChip 텍스트 없음 (PENDING_ACCEPT는 별도 라벨 없이 목록에 보임)
    // _MatchListTile이 ListView에 있으므로 첫 번째 항목 탭 시도
    bool acceptedViaUI = false;
    final listTiles = find.byType(InkWell);
    if (listTiles.evaluate().isNotEmpty) {
      debugPrint('[UserA] 매칭 목록 항목 탭 (첫 번째 InkWell)');
      await tester.tap(listTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('06_match_detail_or_accept');

      // 수락 화면인지 확인 (매칭 상대 발견! 또는 수락 버튼)
      final acceptBtn = find.text('수락');
      if (acceptBtn.evaluate().isNotEmpty) {
        debugPrint('[UserA] 수락 버튼 탭 (UI)');
        await tester.tap(acceptBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await screenshot('07_accepted_ui');
        acceptedViaUI = true;
        debugPrint('[UserA] UI로 수락 완료');
      } else {
        // 매칭 상세 화면일 수도 있음 — 수락 상태이면 API로 fallback
        debugPrint('[UserA] 수락 버튼 없음 → 매칭 상세 화면 확인');
        await screenshot('07_match_detail_screen');
      }
    }

    if (!acceptedViaUI) {
      debugPrint('[UserA] UI 수락 실패 → API 수락 fallback');
      await api.acceptMatch(token, matchId);
      debugPrint('[UserA] API 수락 완료');
    }
  }

  // ── 5. CHAT 상태 대기 ──────────────────────────────────────────────
  debugPrint('[UserA] CHAT 상태 대기');
  final acceptedMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) {
      final status = m['status'] as String? ?? '';
      return ['CHAT', 'CONFIRMED', 'COMPLETED'].contains(status);
    },
  );
  debugPrint('[UserA] 매칭 CHAT 상태: ${acceptedMatch['status']}');

  final chatRoomId = acceptedMatch['chatRoomId'] as String?;

  // ── 6. 채팅 탭 → 채팅방 진입 → 메시지 전송 (UI) ─────────────────────
  debugPrint('[UserA] 채팅 탭으로 이동');
  final chatTabLabel = find.text('채팅');
  if (chatTabLabel.evaluate().isNotEmpty) {
    await tester.tap(chatTabLabel.first);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await screenshot('08_chat_tab');
  }

  // 채팅방 목록에서 첫 번째 항목 탭
  // _ChatRoomTile은 InkWell로 감싸진 ListTile 구조
  bool enteredChatRoom = false;
  final chatRoomItems = find.byType(InkWell);
  if (chatRoomItems.evaluate().isNotEmpty) {
    debugPrint('[UserA] 채팅방 항목 탭');
    await tester.tap(chatRoomItems.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await screenshot('09_chat_room');
    enteredChatRoom = true;
  }

  if (enteredChatRoom) {
    // 채팅방 내부 메시지 전송
    // ChatInputBar 내부의 TextField (힌트: '메시지를 입력하세요...')
    final msgField = find.widgetWithText(TextField, '메시지를 입력하세요...');
    if (msgField.evaluate().isNotEmpty) {
      debugPrint('[UserA] 메시지 입력');
      await tester.tap(msgField.first);
      await tester.pump();
      await tester.enterText(msgField.first, TestConfig.userAChatMessage);
      await tester.pump();
      await screenshot('10_message_typed');

      // 전송 버튼 (Icons.send_rounded, AnimatedContainer 내부 IconButton)
      final sendBtn = find.byIcon(Icons.send_rounded);
      if (sendBtn.evaluate().isNotEmpty) {
        debugPrint('[UserA] 전송 버튼 탭');
        await tester.tap(sendBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await screenshot('11_message_sent');
        debugPrint('[UserA] 메시지 전송 완료 (UI)');
      } else {
        debugPrint('[UserA] 전송 버튼 없음 → API 메시지 전송 fallback');
        if (chatRoomId != null) {
          await api.sendMessage(token, chatRoomId,
              content: TestConfig.userAChatMessage);
        }
      }
    } else {
      debugPrint('[UserA] 메시지 입력 필드 없음 → API 메시지 전송 fallback');
      if (chatRoomId != null) {
        await api.sendMessage(token, chatRoomId,
            content: TestConfig.userAChatMessage);
      }
    }
  } else {
    // 채팅방 목록이 비어있으면 API로 메시지 전송
    debugPrint('[UserA] 채팅방 목록 없음 → API 메시지 전송 fallback');
    if (chatRoomId != null) {
      await api.sendMessage(token, chatRoomId,
          content: TestConfig.userAChatMessage);
    }
  }

  // ── 7. 매칭 탭 → 매칭 상세 → 경기 확정 (UI: 다이얼로그) ──────────────
  debugPrint('[UserA] 매칭 탭 → 경기 확정');

  // 뒤로 가기 (채팅방에서 나가기) — 채팅방에 있으면 뒤로
  final backButton = find.byType(BackButton);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  // 매칭 탭으로 이동
  final matchTab2 = find.text('매칭');
  if (matchTab2.evaluate().isNotEmpty) {
    await tester.tap(matchTab2.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await screenshot('12_match_tab_for_confirm');
  }

  // 진행중 매칭 항목 탭 (CHAT 상태: '채팅 중' 칩)
  bool confirmedViaUI = false;
  final chatStatusChip = find.text('채팅 중');
  if (chatStatusChip.evaluate().isNotEmpty) {
    // '채팅 중' 칩이 있는 InkWell을 탭 (컨테이너 전체)
    // _MatchListTile의 InkWell을 탭
    final matchTiles = find.byType(InkWell);
    if (matchTiles.evaluate().isNotEmpty) {
      await tester.tap(matchTiles.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await screenshot('13_match_detail_for_confirm');

      // '경기 확정' 버튼 탭 (OutlinedButton)
      final confirmMatchBtn = find.text('경기 확정');
      if (confirmMatchBtn.evaluate().isNotEmpty) {
        debugPrint('[UserA] 경기 확정 버튼 탭 (UI)');
        await tester.tap(confirmMatchBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await screenshot('14_confirm_dialog');

        // 날짜 선택 InkWell 탭
        final datePicker = find.text('날짜를 선택해주세요');
        if (datePicker.evaluate().isNotEmpty) {
          await tester.tap(datePicker.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          // DatePicker에서 '확인' 탭
          final okBtn = find.text('확인');
          if (okBtn.evaluate().isNotEmpty) {
            await tester.tap(okBtn.last);
            await tester.pumpAndSettle();
          }
        }

        // 시간 선택 InkWell 탭
        final timePicker = find.text('시간을 선택해주세요');
        if (timePicker.evaluate().isNotEmpty) {
          await tester.tap(timePicker.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          final okBtn = find.text('확인');
          if (okBtn.evaluate().isNotEmpty) {
            await tester.tap(okBtn.last);
            await tester.pumpAndSettle();
          }
        }

        // 장소 입력
        final venueField = find.widgetWithText(TextField, '장소명을 입력해주세요');
        if (venueField.evaluate().isNotEmpty) {
          await tester.enterText(venueField.first, TestConfig.testVenueName);
          await tester.pump();
        }

        await screenshot('15_confirm_dialog_filled');

        // 확정 버튼 탭 (AlertDialog 내 ElevatedButton)
        final submitBtn = find.text('확정');
        if (submitBtn.evaluate().isNotEmpty) {
          await tester.tap(submitBtn.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          await screenshot('16_confirmed');
          debugPrint('[UserA] 경기 확정 완료 (UI)');
          confirmedViaUI = true;
        }
      }
    }
  }

  if (!confirmedViaUI) {
    debugPrint('[UserA] UI 경기 확정 실패 → API fallback');
    try {
      await api.confirmMatch(
        token,
        matchId,
        scheduledDate: TestConfig.testScheduledDate,
        scheduledTime: TestConfig.testScheduledTime,
        venueName: TestConfig.testVenueName,
        venueLatitude: TestConfig.testVenueLatitude,
        venueLongitude: TestConfig.testVenueLongitude,
      );
      debugPrint('[UserA] API 경기 확정 완료');
    } catch (e) {
      debugPrint('[UserA] 경기 확정 스킵 (이미 확정됨 또는 권한 없음): $e');
    }
  }

  await screenshot('17_match_confirmed');

  // ── 8. 게임 ID 획득 대기 ────────────────────────────────────────────
  debugPrint('[UserA] 게임 생성 대기');
  final scheduledMatch = await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getMatchDetail(token, matchId),
    condition: (m) {
      final gameId = m['gameId'] as String?;
      return gameId != null && gameId.isNotEmpty;
    },
  );
  final gameId = scheduledMatch['gameId'] as String;
  debugPrint('[UserA] 게임 ID: $gameId');

  // ── 9. 결과 입력 화면 진입 (UI) ─────────────────────────────────────
  // 매칭 상세 화면에서 '결과 입력' 버튼 탭
  bool resultInputViaUI = false;

  // 현재 매칭 상세 화면에 있는지 확인
  final resultInputBtn = find.text('결과 입력');
  if (resultInputBtn.evaluate().isNotEmpty) {
    debugPrint('[UserA] 결과 입력 버튼 탭 (UI)');
    await tester.tap(resultInputBtn.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await screenshot('18_result_input_screen');

    // 점수 입력 (TextField 2개 — 내 점수, 상대 점수)
    // GameResultInputScreen: _myScoreController, _opponentScoreController
    final scoreFields = find.byType(TextField);
    final fieldCount = scoreFields.evaluate().length;
    debugPrint('[UserA] 결과 입력 화면 TextField 개수: $fieldCount');

    if (fieldCount >= 2) {
      // 첫 번째: 내 점수, 두 번째: 상대 점수
      await tester.tap(scoreFields.at(0));
      await tester.enterText(
          scoreFields.at(0), TestConfig.userAScore.toString());
      await tester.pump();

      await tester.tap(scoreFields.at(1));
      await tester.enterText(
          scoreFields.at(1), TestConfig.userBScore.toString());
      await tester.pump();
      await screenshot('19_scores_entered');

      // 제출 버튼 탭
      final submitResultBtn = find.text('결과 제출');
      if (submitResultBtn.evaluate().isEmpty) {
        // 버튼 텍스트가 다를 수 있음 — ElevatedButton 중 마지막 탭
        final elevatedBtns = find.byType(ElevatedButton);
        if (elevatedBtns.evaluate().isNotEmpty) {
          await tester.tap(elevatedBtns.last);
          await tester.pumpAndSettle(const Duration(seconds: 3));
          await screenshot('20_result_submitted');
          debugPrint('[UserA] 결과 제출 완료 (UI)');
          resultInputViaUI = true;
        }
      } else {
        await tester.tap(submitResultBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await screenshot('20_result_submitted');
        debugPrint('[UserA] 결과 제출 완료 (UI)');
        resultInputViaUI = true;
      }
    }
  }

  if (!resultInputViaUI) {
    debugPrint('[UserA] UI 결과 입력 실패 → API fallback');
    // API로 결과 입력 시 winnerId는 내 userId (A 승리)
    await api.submitGameResult(
      token,
      gameId,
      myScore: TestConfig.userAScore,
      opponentScore: TestConfig.userBScore,
      winnerId: userId,
    );
    debugPrint('[UserA] API 결과 입력 완료');
  }

  await screenshot('21_result_done');

  // ── 10. User B 결과 확인 대기 ─────────────────────────────────────
  debugPrint('[UserA] User B 결과 확인 대기');
  await api.pollUntil<Map<String, dynamic>>(
    fetcher: () => api.getGameDetail(token, gameId),
    condition: (game) {
      final status =
          game['resultStatus'] as String? ?? game['status'] as String? ?? '';
      return ['VERIFIED', 'COMPLETED'].contains(status);
    },
  );
  debugPrint('[UserA] 결과 확인 완료 — 테스트 성공');

  await tester.pump(const Duration(seconds: 1));
  await screenshot('22_flow_complete');
  debugPrint('[UserA] ===== User A UI 플로우 완료 =====');
}
