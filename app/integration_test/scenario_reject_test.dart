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

/// 시나리오 — 경기요청 거절(reject)
///
/// 검증:
///   1. PENDING_ACCEPT 상태에서 거절 → 매칭 CANCELLED
///   2. 거절자 -5점 페널티, 수락자(상대) +5점 보상
///   3. 거절 후 점수가 홈/프로필에 새로고침 없이 반영
///
/// role A = 수락자(+5점), role B = 거절자(-5점)
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

  const isRejecter = role == 'B';

  testWidgets(
    '경기요청 거절 — 역할: $role',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      debugPrint('[RJ-$role] 시작 userId=$userId');

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
        message: 'reject test $role',
      );
      debugPrint('[RJ-$role] 매칭 요청 생성');

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
      debugPrint('[RJ-$role] 앱 기동 완료');
      await _shot(role, '01_app_ready');

      // ── phase 3: PENDING_ACCEPT 매칭 확보 + 거절 전 점수 기록 ──
      final pending = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) => m['status'] == 'PENDING_ACCEPT')
              .toList();
          if (f.isEmpty) throw Exception('no pending match');
          return f.first;
        },
        condition: (m) => true,
        maxAttempts: 60,
      );
      final matchId = pending['id'] as String;
      debugPrint('[RJ-$role] PENDING_ACCEPT 매칭 — matchId=$matchId');
      await _shot(role, '02_accept_screen');

      final beforeProfiles = await api.getSportsProfiles(accessToken);
      final scoreBefore = _scoreOf(beforeProfiles, TestConfig.testSportType);
      debugPrint('[RJ-$role] 거절 전 점수: $scoreBefore');

      // ── phase 4: A 수락 먼저 → B 거절 ──
      // 수락자 보상(+5)은 "상대가 수락한 경우에만" 적용되므로 A 가 먼저 수락한다.
      if (isRejecter) {
        // B(거절자): A 가 수락할 시간을 준 뒤 거절
        await Future.delayed(const Duration(seconds: 8));
        await api.rejectMatch(accessToken, matchId);
        debugPrint('[RJ-$role] rejectMatch 호출');
      } else {
        // A(수락자): 즉시 수락
        await api.acceptMatch(accessToken, matchId);
        debugPrint('[RJ-$role] acceptMatch 호출 — 상대 거절 대기');
      }

      // ── phase 5: 매칭 CANCELLED 대기 ──
      final cancelled = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) => (m['status'] as String? ?? '') == 'CANCELLED',
        maxAttempts: 40,
      );
      expect(cancelled['status'], 'CANCELLED');
      debugPrint('[RJ-$role] 매칭 CANCELLED 확인');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '03_after_reject');

      // ── phase 6: 점수 변동 검증 ──
      final afterProfiles = await api.getSportsProfiles(accessToken);
      final scoreAfter = _scoreOf(afterProfiles, TestConfig.testSportType);
      debugPrint('[RJ-$role] 거절 후 점수: $scoreAfter (전: $scoreBefore)');
      if (isRejecter) {
        expect(scoreAfter < scoreBefore, true,
            reason: '거절자 점수가 하락하지 않음 ($scoreBefore → $scoreAfter)');
      } else {
        expect(scoreAfter > scoreBefore, true,
            reason: '수락자 보상 점수가 반영되지 않음 ($scoreBefore → $scoreAfter)');
      }
      debugPrint('[RJ-$role] OK 점수 변동 검증');

      // ── phase 7: 홈/매칭목록/프로필 반영 확인 (스크린샷) ──
      _forceGo('/home');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '04_home_after');
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '05_match_list_after');
      _forceGo('/profile');
      await _settle(tester, const Duration(seconds: 3));
      await _shot(role, '06_profile_after');

      // 진행중 매칭 목록에 거절된 매칭이 없어야 한다.
      final remaining = await api.getMyMatches(accessToken);
      final stillActive = remaining.any((m) =>
          m['id'] == matchId &&
          ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(m['status']));
      expect(stillActive, false,
          reason: '거절된 매칭이 아직 진행중 상태로 남아있음');

      debugPrint('[RJ-$role] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}
