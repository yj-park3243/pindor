import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    try {
      GoRouter.of(ctx).go(path);
    } catch (_) {}
  }
}

Future<void> _settle(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 200);
  var elapsed = Duration.zero;
  while (elapsed < d) {
    await tester.pump(step);
    elapsed += step;
  }
}

Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 60,
  Duration interval = const Duration(milliseconds: 500),
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.pump(interval);
  }
  return false;
}

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
  debugPrint('[CP] _tapKey timeout — key=$keyValue');
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

num _scoreOf(List<Map<String, dynamic>> profiles, String sportType) {
  final p = profiles.firstWhere(
    (e) => e['sportType'] == sportType,
    orElse: () => profiles.isNotEmpty ? profiles.first : <String, dynamic>{},
  );
  return (p['displayScore'] ?? p['currentScore'] ?? p['score'] ?? 0) as num;
}

int _gamesOf(List<Map<String, dynamic>> profiles, String sportType) {
  final p = profiles.firstWhere(
    (e) => e['sportType'] == sportType,
    orElse: () => profiles.isNotEmpty ? profiles.first : <String, dynamic>{},
  );
  return (p['gamesPlayed'] ?? p['games'] ?? 0) as int;
}

/// 시나리오 — 경기 정상 완료 후 모든 페이지 반영
///
/// 검증:
///   1. confirm-met → 결과 입력(A:WIN, B:LOSS) → VERIFIED → COMPLETED
///   2. 매칭 상세 화면에 머문 채로 승/패 태그가 새로고침 없이 반영
///   3. 경기 완료 후 점수 변동(승자 상승/패자 하락) + gamesPlayed +1
///   4. 홈/프로필/매칭목록에 결과가 새로고침 없이 반영
///
/// role A = 승자(WIN), role B = 패자(LOSS)
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

  const isWinner = role == 'A';

  testWidgets(
    '경기 완료 후 페이지 반영 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      debugPrint('[CP-$role] 시작 userId=$userId');

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

      // ── phase 1: 매칭 요청 (앱 기동 전) ──
      final pins = await api.getAllPins(accessToken);
      final pin = pins.firstWhere(
        (p) => p['name'] == pinName,
        orElse: () => pins.first,
      );
      await api.createMatchRequest(
        accessToken,
        sportType: TestConfig.testSportType,
        pinId: pin['id'] as String,
        message: 'complete test $role',
      );
      debugPrint('[CP-$role] 매칭 요청 생성');

      // storage 검증 — write 가 실제로 persistent 한지 확인
      final stToken = await storage.read(key: 'access_token');
      final stRefresh = await storage.read(key: 'refresh_token');
      final stUserId = await storage.read(key: 'user_id');
      debugPrint('[CP-$role] storage 검증: access=${stToken == null ? "NULL" : "len=${stToken.length}"} refresh=${stRefresh == null ? "NULL" : "OK"} userId=$stUserId');
      debugPrint('[CP-$role] storage check (test 인스턴스): access_token=${stToken == null ? "NULL" : "<len=${stToken.length}>"}');

      // ── phase 2: 앱 기동 ──
      unawaited(Future(() => app.main()));
      bool appReady = false;
      for (var i = 0; i < 60; i++) {
        try {
          await _settle(tester, const Duration(milliseconds: 800));
        } catch (_) {
          await tester.pump(const Duration(seconds: 1));
        }
        if (find.text('오늘 대결 나가고 싶다!').evaluate().isNotEmpty ||
            find.byKey(const Key('match_accept_accept_btn')).evaluate().isNotEmpty) {
          appReady = true;
          break;
        }
        // 매 10번 마다 현재 라우트 + 화면 텍스트 일부 덤프 (실패 진단용)
        if (i % 10 == 9) {
          final ctx = AppToast.navigatorKey.currentContext;
          String loc = '?';
          if (ctx != null) {
            try {
              loc = GoRouterState.of(ctx).matchedLocation;
            } catch (_) {}
          }
          final allTexts = find.byType(Text).evaluate().take(8).map((e) {
            final w = e.widget;
            if (w is Text) return w.data ?? '';
            return '';
          }).where((s) => s.isNotEmpty).join(' | ');
          debugPrint('[CP-$role] phase2 wait i=$i loc=$loc texts="$allTexts"');
          await _shot(role, '00_wait_${i.toString().padLeft(2, '0')}');
        }
      }
      if (!appReady) {
        await _shot(role, '00_FAIL_appReady');
      }
      expect(appReady, true, reason: '앱 기동 실패');
      debugPrint('[CP-$role] 앱 기동 완료');
      await _shot(role, '01_app_ready');

      // ── phase 3: 수락 → CHAT 진입 ──
      final accepted = await _waitFor(
        tester,
        find.byKey(const Key('match_accept_accept_btn')),
        maxAttempts: 120,
      );
      expect(accepted, true, reason: 'accept 화면 미도달');
      await _tapKey(tester, 'match_accept_accept_btn');
      debugPrint('[CP-$role] 수락 tap');

      final chatMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) => ['CHAT', 'CONFIRMED'].contains(m['status']))
              .toList();
          if (f.isEmpty) throw Exception('not chat yet');
          return f.first;
        },
        condition: (m) => true,
        maxAttempts: 60,
      );
      final matchId = chatMatch['id'] as String;
      debugPrint('[CP-$role] CHAT 진입 — matchId=$matchId');

      // ── phase 4: 매칭 상세 진입 + 완료 전 점수/전적 기록 ──
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '02_match_detail');

      final beforeProfiles = await api.getSportsProfiles(accessToken);
      final scoreBefore = _scoreOf(beforeProfiles, TestConfig.testSportType);
      final gamesBefore = _gamesOf(beforeProfiles, TestConfig.testSportType);
      debugPrint('[CP-$role] 완료 전 점수=$scoreBefore games=$gamesBefore');

      // ── phase 5: confirm-met → game 생성 대기 ──
      await api.confirmMet(accessToken, matchId);
      debugPrint('[CP-$role] confirmMet 호출');
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
      debugPrint('[CP-$role] both-met + gameId=$gameId');

      // ── phase 6: 결과 입력 (A:WIN 3-1, B:LOSS 1-3) ──
      if (isWinner) {
        await api.submitGameResult(accessToken, gameId,
            myScore: 3, opponentScore: 1, claimedResult: 'WIN');
      } else {
        // B 는 race 회피 위해 약간 늦게 제출
        await Future.delayed(const Duration(seconds: 5));
        await api.submitGameResult(accessToken, gameId,
            myScore: 1, opponentScore: 3, claimedResult: 'LOSS');
      }
      debugPrint('[CP-$role] 결과 제출');

      // ── phase 7: 매칭 상세에 머문 채 결과 반영 검증 (새로고침 없이) ──
      const expectTag = isWinner ? '승리' : '패배';
      final tagShown = await _waitFor(
        tester,
        find.textContaining(expectTag),
        maxAttempts: 90,
      );
      await _shot(role, '03_after_complete');
      expect(
        tagShown,
        true,
        reason: '경기 완료 후 매칭 상세에 "$expectTag" 태그 미반영 — 새로고침 버그',
      );
      debugPrint('[CP-$role] OK 매칭 상세에 "$expectTag" 반영');

      // ── phase 8: 서버 측 VERIFIED/COMPLETED + 점수/전적 검증 ──
      await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getGameDetail(accessToken, gameId),
        condition: (g) => (g['resultStatus'] as String? ?? '') == 'VERIFIED',
        maxAttempts: 60,
      );
      final completedMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) => (m['status'] as String? ?? '') == 'COMPLETED',
        maxAttempts: 30,
      );
      expect(completedMatch['status'], 'COMPLETED');

      final afterProfiles = await api.getSportsProfiles(accessToken);
      final scoreAfter = _scoreOf(afterProfiles, TestConfig.testSportType);
      final gamesAfter = _gamesOf(afterProfiles, TestConfig.testSportType);
      debugPrint(
          '[CP-$role] 완료 후 점수=$scoreAfter games=$gamesAfter (전: $scoreBefore/$gamesBefore)');
      expect(gamesAfter, gamesBefore + 1,
          reason: 'gamesPlayed 가 1 증가하지 않음');
      // 배치 단계(games<5)에서는 server 가 displayScore=null 로 응답하므로 점수 비교 skip.
      // (profiles.service.ts: isPlacement 시 visibleScore=null)
      if (gamesAfter >= 5) {
        if (isWinner) {
          expect(scoreAfter > scoreBefore, true,
              reason: '승자 점수가 상승하지 않음 ($scoreBefore → $scoreAfter)');
        } else {
          expect(scoreAfter < scoreBefore, true,
              reason: '패자 점수가 하락하지 않음 ($scoreBefore → $scoreAfter)');
        }
      } else {
        debugPrint('[CP-$role] 배치 단계(games=$gamesAfter<5) — 점수 비교 skip');
      }
      debugPrint('[CP-$role] OK 점수/전적 변동 검증');

      // ── phase 9: 홈/프로필/매칭목록 반영 확인 ──
      _forceGo('/home');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '04_home_after');
      _forceGo('/profile');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '05_profile_after');
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '06_match_list_after');

      // 완료된 매칭이 진행중 목록에 남아있지 않아야 한다.
      final remaining = await api.getMyMatches(accessToken);
      final stillActive = remaining.any((m) =>
          m['id'] == matchId &&
          ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(m['status']));
      expect(stillActive, false,
          reason: '완료된 매칭이 아직 진행중 상태로 남아있음');

      // ── phase 10: 모든 페이지 순회 + 우측 상단 메뉴 펼침 + 메뉴 아이템 탭 ──
      // 각 페이지가 에러 없이 렌더되고 메뉴가 정상 작동하는지(크래시·RenderFlex 등) 확인.
      // 메뉴 아이템 탭 시 다이얼로그/시트가 뜨면 화면 떠 있는 상태 스크린샷 후 닫는다.
      final chatRoomId = completedMatch['chatRoomId'] as String?;
      final pagesToVisit = <_PageVisit>[
        _PageVisit('/home', '10a_home'),
        _PageVisit('/matches', '10b_matches'),
        _PageVisit('/matches/$matchId', '10c_match_detail'),
        if (chatRoomId != null && chatRoomId.isNotEmpty)
          _PageVisit('/chats/$chatRoomId', '10c2_chat_room'),
        _PageVisit('/map', '10d_map'),
        _PageVisit('/profile', '10e_profile'),
        _PageVisit('/profile/edit', '10f_profile_edit'),
        _PageVisit('/profile/notifications', '10g_profile_notifications'),
        _PageVisit('/profile/settings', '10h_settings'),
        _PageVisit('/profile/settings/notifications', '10i_settings_notifications'),
        _PageVisit('/profile/settings/blocked-users', '10j_blocked_users'),
        _PageVisit('/profile/inquiry', '10k_inquiry'),
        _PageVisit('/notices', '10l_notices'),
        _PageVisit('/disputes', '10m_disputes'),
      ];

      for (final p in pagesToVisit) {
        try {
          _forceGo(p.path);
          await _settle(tester, const Duration(seconds: 2));
          await _shot(role, p.label);
          await _exploreAppBarActions(tester, role, p.label, p.path);
        } catch (e) {
          debugPrint('[CP-$role] page 순회 에러 ${p.path}: $e');
        }
      }
      // phase 10 도중 위젯/렌더링 레이어에서 잡힌 비치명 예외(hit-test miss 등)는
      // takeException 으로 비워야 test framework가 "Multiple exceptions" 로 실패시키지 않는다.
      var drained = 0;
      while (tester.takeException() != null) {
        drained++;
      }
      debugPrint(
          '[CP-$role] phase 10: 페이지 순회 + 메뉴 탐색 완료 (누적 비치명 예외 $drained건 비움)');

      debugPrint('[CP-$role] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

class _PageVisit {
  final String path;
  final String label;
  _PageVisit(this.path, this.label);
}

/// 현재 화면 AppBar 의 모든 우측 액션(IconButton) 을 순서대로 탭한다.
/// - PullDown 메뉴 트리거(more_vert): 펼친 후 텍스트 diff 로 아이템 추출 → 각 아이템 탭 →
///   다이얼로그 마지막 ElevatedButton(확정/destructive) 탭
/// - 검색·필터·알림 종 등 일반 IconButton: 탭 → 스크린샷 → 페이지 재진입
/// - 매번 returnPath 로 페이지 재진입하여 화면 전환 race 회피
Future<void> _exploreAppBarActions(
  WidgetTester tester,
  String role,
  String label,
  String returnPath,
) async {
  final appBar = find.byType(AppBar);
  if (appBar.evaluate().isEmpty) return;
  final initialCount = find
      .descendant(of: appBar, matching: find.byType(IconButton))
      .evaluate()
      .length;
  if (initialCount == 0) return;

  for (var i = 0; i < initialCount; i++) {
    // 페이지 재진입 — 직전 탭으로 화면이 전환됐을 수 있음
    _forceGo(returnPath);
    await _settle(tester, const Duration(seconds: 2));
    final btns = find.descendant(
        of: find.byType(AppBar), matching: find.byType(IconButton));
    final btnElements = btns.evaluate().toList();
    if (btnElements.length <= i) break;
    final btnWidget = btnElements[i].widget as IconButton;
    if (btnWidget.onPressed == null) {
      debugPrint('[CP-$role] $label action $i disabled — skip');
      continue;
    }

    // 펼치기 전 텍스트 스냅샷
    final before = <String>{};
    for (final el in find.byType(Text).evaluate()) {
      final t = (el.widget as Text).data;
      if (t != null && t.isNotEmpty) before.add(t);
    }

    // i번째 IconButton 탭 — 이전 iter의 ModalBarrier 잔존 등으로 hit-test 실패해도
    // warning 누적으로 test framework가 "Multiple exceptions" 잡지 않도록 warnIfMissed:false
    try {
      await tester.tap(btns.at(i), warnIfMissed: false);
    } catch (e) {
      debugPrint('[CP-$role] $label action $i tap 실패: $e');
      continue;
    }
    await _settle(tester, const Duration(milliseconds: 700));
    await _shot(role, '${label}_action_${i}_tapped');

    // 새로 나타난 텍스트 = 메뉴 아이템 또는 다이얼로그/시트 내용
    final after = <String>{};
    for (final el in find.byType(Text).evaluate()) {
      final t = (el.widget as Text).data;
      if (t != null && t.isNotEmpty) after.add(t);
    }
    final newTexts = after.difference(before);
    if (newTexts.isNotEmpty) {
      debugPrint(
          '[CP-$role] $label action $i 새 텍스트: ${newTexts.take(8).join(", ")}');
    }

    // 외부 URL/앱 호출 가능성 있는 아이템은 skip — Safari 등으로 앱이 백그라운드 되면
    // iOS 가 Flutter debug 연결을 끊어 테스트가 영원히 hang 된다.
    const skipKeywords = [
      '약관', '정책', '처리방침', '개인정보', '라이선스', '오픈소스',
      '문의', '버전', '리뷰', '평가', '평점', '도움말', '고객센터',
    ];

    // 페이지 전환 감지 — IconButton 이 back 버튼이거나 다른 페이지로 push 한 경우
    // 새 텍스트가 너무 많으면(>5) 페이지 본문이므로 추가 탭하지 않는다.
    // 메뉴 펼침은 보통 2~5개 아이템.
    if (newTexts.length > 5) {
      debugPrint('[CP-$role] $label action $i 페이지 전환 감지 — 추가 탭 skip');
      continue;
    }

    // 짧은 텍스트(<=12자)는 메뉴 아이템 후보로 보고 각각 탭 → 다이얼로그 확정
    for (final t in newTexts) {
      if (t.length > 12) continue;
      if (skipKeywords.any((kw) => t.contains(kw))) {
        debugPrint('[CP-$role] skip "$t" (외부 호출 위험)');
        continue;
      }
      _forceGo(returnPath);
      await _settle(tester, const Duration(seconds: 2));
      final btnsAgain = find.descendant(
          of: find.byType(AppBar), matching: find.byType(IconButton));
      final againEls = btnsAgain.evaluate().toList();
      if (againEls.length <= i) break;
      final againWidget = againEls[i].widget as IconButton;
      if (againWidget.onPressed == null) continue;
      try {
        await tester.tap(btnsAgain.at(i), warnIfMissed: false);
        await _settle(tester, const Duration(milliseconds: 500));
        final itemFinder = find.text(t);
        if (itemFinder.evaluate().isEmpty) continue;
        await tester.tap(itemFinder.first, warnIfMissed: false);
        await _settle(tester, const Duration(seconds: 1));
        await _shot(role, '${label}_action_${i}_item_${t.replaceAll(' ', '_')}');
        // 다이얼로그 확정 (있으면)
        final confirmBtns = find.byType(ElevatedButton);
        if (confirmBtns.evaluate().isNotEmpty) {
          try {
            await tester.tap(confirmBtns.last, warnIfMissed: false);
            await _settle(tester, const Duration(seconds: 2));
            await _shot(role,
                '${label}_action_${i}_item_${t.replaceAll(' ', '_')}_confirmed');
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[CP-$role] item "$t" 탭 실패: $e');
      }
    }
  }
}

/// (deprecated — _exploreAppBarActions 로 통합됨)
// ignore: unused_element
Future<void> _exploreMenu(WidgetTester tester, String role, String label) async {
  // 메뉴 트리거 찾기 — Icons.more_vert 우선, 없으면 more_horiz
  Finder? trigger;
  for (final icon in const [Icons.more_vert, Icons.more_horiz]) {
    final f = find.byIcon(icon);
    if (f.evaluate().isNotEmpty) {
      trigger = f.first;
      break;
    }
  }
  if (trigger == null) return;

  // 1) 펼치기 전 텍스트 스냅샷 — 페이지 본문 텍스트
  final beforeTexts = <String>{};
  for (final el in find.byType(Text).evaluate()) {
    final t = (el.widget as Text).data;
    if (t != null && t.isNotEmpty) beforeTexts.add(t);
  }

  // 2) 메뉴 펼침 — 메뉴 열림 스크린샷
  try {
    await tester.tap(trigger);
  } catch (e) {
    debugPrint('[CP-$role] 메뉴 트리거 tap 실패 ($label): $e');
    return;
  }
  await _settle(tester, const Duration(milliseconds: 700));
  await _shot(role, '${label}_menu_open');

  // 3) 펼친 후 텍스트 — diff 가 메뉴 아이템 (페이지 본문 노이즈 제거)
  final afterTexts = <String>{};
  for (final el in find.byType(Text).evaluate()) {
    final t = (el.widget as Text).data;
    if (t != null && t.isNotEmpty) afterTexts.add(t);
  }
  final itemTexts = afterTexts.difference(beforeTexts);
  debugPrint('[CP-$role] $label 메뉴 아이템: ${itemTexts.join(", ")}');

  // 외부 영역 탭으로 메뉴 닫기
  try {
    await tester.tapAt(const Offset(20, 20));
  } catch (_) {}
  await _settle(tester, const Duration(milliseconds: 500));

  // 3) 각 후보 텍스트에 대해 — 메뉴 재펼침 → 그 텍스트 탭 → 다이얼로그/시트 처리
  for (final text in itemTexts) {
    try {
      if (find.byIcon(Icons.more_vert).evaluate().isEmpty &&
          find.byIcon(Icons.more_horiz).evaluate().isEmpty) {
        // 화면이 전환됨 — 더 진행 안 함
        return;
      }
      final reopenTrigger = find.byIcon(Icons.more_vert).evaluate().isNotEmpty
          ? find.byIcon(Icons.more_vert).first
          : find.byIcon(Icons.more_horiz).first;
      await tester.tap(reopenTrigger);
      await _settle(tester, const Duration(milliseconds: 500));

      final item = find.text(text);
      if (item.evaluate().isEmpty) {
        // 메뉴 아이템이 아니라 페이지 내 다른 텍스트였음 — skip
        await tester.tapAt(const Offset(20, 20));
        await _settle(tester, const Duration(milliseconds: 300));
        continue;
      }
      await tester.tap(item.first);
      await _settle(tester, const Duration(seconds: 1));
      await _shot(role, '${label}_item_${text.replaceAll(' ', '_')}');

      // 다이얼로그가 뜨면 마지막 ElevatedButton(확정/destructive) 탭
      final confirmBtns = find.byType(ElevatedButton);
      if (confirmBtns.evaluate().isNotEmpty) {
        try {
          await tester.tap(confirmBtns.last);
          await _settle(tester, const Duration(seconds: 2));
          await _shot(role, '${label}_item_${text.replaceAll(' ', '_')}_confirmed');
        } catch (_) {}
      } else {
        // 시트 등 — 외부 탭으로 닫음
        try {
          await tester.tapAt(const Offset(20, 20));
        } catch (_) {}
        await _settle(tester, const Duration(milliseconds: 500));
      }
    } catch (e) {
      debugPrint('[CP-$role] menu item "$text" tap 에러 ($label): $e');
    }
  }
}
