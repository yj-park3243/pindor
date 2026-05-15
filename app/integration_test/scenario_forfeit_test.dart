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
  debugPrint('[FF] _tapKey timeout — key=$keyValue');
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

/// sports-profiles 응답에서 해당 종목의 점수를 뽑는다 (displayScore 우선).
num _scoreOf(List<Map<String, dynamic>> profiles, String sportType) {
  final p = profiles.firstWhere(
    (e) => e['sportType'] == sportType,
    orElse: () => profiles.isNotEmpty ? profiles.first : <String, dynamic>{},
  );
  return (p['displayScore'] ?? p['currentScore'] ?? p['score'] ?? 0) as num;
}

/// 시나리오 — 경기 포기(forfeit)
///
/// 검증:
///   1. CHAT 상태에서 포기 가능 (서버 수정 — 이전엔 PENDING_ACCEPT 만 허용)
///   2. 포기 시 포기자 패배(점수 하락) / 상대 승리(점수 상승)
///   3. 매칭 상세 화면에 머문 채로 포기 결과(승/패 태그)가 새로고침 없이 반영
///   4. 포기 후 매칭 상태 COMPLETED
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

  // role A = 포기자(패배), role B = 상대(승자)
  const isForfeiter = role == 'A';

  testWidgets(
    '경기 포기 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      debugPrint('[FF-$role] 시작 userId=$userId');

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
        message: 'forfeit test $role',
      );
      debugPrint('[FF-$role] 매칭 요청 생성');

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
      debugPrint('[FF-$role] 앱 기동 완료');
      await _shot(role, '01_app_ready');

      // ── phase 3: 수락 → CHAT 진입 ──
      final accepted = await _waitFor(
        tester,
        find.byKey(const Key('match_accept_accept_btn')),
        maxAttempts: 120,
      );
      expect(accepted, true, reason: 'accept 화면 미도달 (MATCH_FOUND 실패)');
      await _tapKey(tester, 'match_accept_accept_btn');
      debugPrint('[FF-$role] 수락 tap');

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
      debugPrint('[FF-$role] CHAT 진입 — matchId=$matchId');

      // ── phase 4: 매칭 상세 진입 + 포기 전 점수 기록 ──
      _forceGo('/matches/$matchId');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '02_match_detail');

      final beforeProfiles = await api.getSportsProfiles(accessToken);
      final scoreBefore = _scoreOf(beforeProfiles, TestConfig.testSportType);
      debugPrint('[FF-$role] 포기 전 점수: $scoreBefore');

      // ── phase 5: 포기 (A 만 수행, B 는 대기) ──
      if (isForfeiter) {
        await api.forfeitMatch(accessToken, matchId);
        debugPrint('[FF-$role] forfeitMatch 호출 (CHAT 상태에서 포기)');
      } else {
        debugPrint('[FF-$role] 상대 포기 대기');
      }

      // ── phase 6: 매칭 상세에 머문 채 결과 반영 검증 (새로고침 없이) ──
      // 포기자=패배 태그, 상대=승리 태그가 화면에 나타나야 한다.
      const expectTag = isForfeiter ? '패배' : '승리';
      final tagShown = await _waitFor(
        tester,
        find.textContaining(expectTag),
        maxAttempts: 80,
      );
      await _shot(role, '03_after_forfeit');
      expect(
        tagShown,
        true,
        reason: '포기 후 매칭 상세에 "$expectTag" 태그 미반영 — 새로고침 버그',
      );
      debugPrint('[FF-$role] OK 매칭 상세에 "$expectTag" 반영');

      // ── phase 7: 서버 측 점수/상태 검증 ──
      final completedMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) => (m['status'] as String? ?? '') == 'COMPLETED',
        maxAttempts: 30,
      );
      expect(completedMatch['status'], 'COMPLETED');

      final afterProfiles = await api.getSportsProfiles(accessToken);
      final scoreAfter = _scoreOf(afterProfiles, TestConfig.testSportType);
      debugPrint('[FF-$role] 포기 후 점수: $scoreAfter (전: $scoreBefore)');
      if (isForfeiter) {
        expect(scoreAfter < scoreBefore, true,
            reason: '포기자 점수가 하락하지 않음 ($scoreBefore → $scoreAfter)');
      } else {
        expect(scoreAfter > scoreBefore, true,
            reason: '승자 점수가 상승하지 않음 ($scoreBefore → $scoreAfter)');
      }
      debugPrint('[FF-$role] OK 점수 변동 검증');

      // ── phase 8: 홈/프로필 화면 반영 확인 (스크린샷) ──
      _forceGo('/home');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '04_home_after');
      _forceGo('/profile');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '05_profile_after');

      debugPrint('[FF-$role] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
