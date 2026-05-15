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
      if (isWinner) {
        expect(scoreAfter > scoreBefore, true,
            reason: '승자 점수가 상승하지 않음 ($scoreBefore → $scoreAfter)');
      } else {
        expect(scoreAfter < scoreBefore, true,
            reason: '패자 점수가 하락하지 않음 ($scoreBefore → $scoreAfter)');
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

      debugPrint('[CP-$role] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
