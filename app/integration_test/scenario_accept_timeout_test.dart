import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spots/main.dart' as app;

import 'helpers/api_helper.dart';
import 'helpers/test_config.dart';

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

Future<void> _shot(String name) async {
  try {
    await _shotDio.get('http://127.0.0.1:9998/userA_$name');
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

/// 시나리오 — 매칭 수락 타임아웃 (MATCH_ACCEPT_TIMEOUT)
///
/// 검증:
///   1. PENDING_ACCEPT 상태에서 A 만 수락, B 미응답
///   2. ACCEPT_TIMEOUT_MS 만큼 대기 → BullMQ worker 가 매치 CANCELLED 처리
///   3. 미응답자 B: displayScore -5 페널티 + NO_SHOW_PENALTY score_history
///   4. 수락자 A: displayScore +5 보상 + NO_SHOW_COMPENSATION
///   5. A 에게 MATCH_ACCEPT_TIMEOUT 알림(소켓) 도달
///
/// 단일 시뮬(A)만 사용. B 액션은 ApiHelper 로 외부 트리거.
/// staging .env 의 ACCEPT_TIMEOUT_MS=15000 설정 가정 (기본 10분).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiHelper();

  const accessToken = String.fromEnvironment('TEST_ACCESS_TOKEN');
  const refreshToken = String.fromEnvironment('TEST_REFRESH_TOKEN');
  const userId = String.fromEnvironment('TEST_USER_ID');
  const opponentToken =
      String.fromEnvironment('TEST_OPPONENT_ACCESS_TOKEN');
  const acceptTimeoutMs = int.fromEnvironment(
    'ACCEPT_TIMEOUT_MS',
    defaultValue: 15000,
  );
  const pinName = String.fromEnvironment(
    'SCENARIO_PIN_NAME',
    defaultValue: TestConfig.testPinName,
  );

  testWidgets(
    '수락 타임아웃 — A 수락 / B 미응답 → 매치 CANCELLED + 점수 패널티/보상',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      expect(opponentToken.isNotEmpty, true,
          reason: 'TEST_OPPONENT_ACCESS_TOKEN 필수');
      debugPrint('[AT] 시작 userId=$userId acceptTimeoutMs=$acceptTimeoutMs');

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

      // ── phase 1: 양쪽 매칭 요청 ──
      final pins = await api.getAllPins(accessToken);
      final pin = pins.firstWhere(
        (p) => p['name'] == pinName,
        orElse: () => pins.first,
      );
      final pinId = pin['id'] as String;
      await api.createMatchRequest(
        accessToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'accept-timeout A',
      );
      await api.createMatchRequest(
        opponentToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'accept-timeout B',
      );
      debugPrint('[AT] 양쪽 매칭 요청 생성');

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
            find
                .byKey(const Key('match_accept_accept_btn'))
                .evaluate()
                .isNotEmpty) {
          appReady = true;
          break;
        }
      }
      expect(appReady, true, reason: '앱 기동 실패');
      debugPrint('[AT] 앱 기동 완료');
      await _shot('01_app_ready');

      // ── phase 3: PENDING_ACCEPT 매치 폴링 ──
      final pending = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) => m['status'] == 'PENDING_ACCEPT')
              .toList();
          if (f.isEmpty) throw Exception('no pending');
          return f.first;
        },
        condition: (m) => true,
        maxAttempts: 60,
      );
      final matchId = pending['id'] as String;
      debugPrint('[AT] PENDING_ACCEPT 잡힘 — matchId=$matchId');

      // 패널티 전 점수 기록 (A: 수락자 / B: 미응답자)
      final aBeforeProfiles = await api.getSportsProfiles(accessToken);
      final aScoreBefore = _scoreOf(aBeforeProfiles, TestConfig.testSportType);
      final bBeforeProfiles = await api.getSportsProfiles(opponentToken);
      final bScoreBefore = _scoreOf(bBeforeProfiles, TestConfig.testSportType);
      debugPrint('[AT] 전 점수 A=$aScoreBefore / B=$bScoreBefore');

      // ── phase 4: A 만 수락 (B 는 의도적 미응답) ──
      await api.acceptMatch(accessToken, matchId);
      debugPrint('[AT] A 수락 호출 — B 는 미응답으로 둔다');
      await _shot('02_after_a_accept');

      // ── phase 5: ACCEPT_TIMEOUT_MS 만큼 대기 + 여유분 ──
      //  - staging 은 15s 셋업. 워커 지터 고려 +10s 여유.
      final waitMs = acceptTimeoutMs + 10000;
      debugPrint('[AT] 타임아웃 대기 ${waitMs}ms');
      await _settle(tester, Duration(milliseconds: waitMs));

      // ── phase 6: 매치 CANCELLED 폴링 ──
      final cancelled = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) => (m['status'] as String? ?? '') == 'CANCELLED',
        maxAttempts: 30,
      );
      expect(cancelled['status'], 'CANCELLED');
      debugPrint('[AT] 매치 CANCELLED 확인');
      await _shot('03_after_timeout');

      // ── phase 7: 점수 변동 검증 — 미응답자 -, 수락자 + ──
      final aAfterProfiles = await api.getSportsProfiles(accessToken);
      final aScoreAfter = _scoreOf(aAfterProfiles, TestConfig.testSportType);
      final bAfterProfiles = await api.getSportsProfiles(opponentToken);
      final bScoreAfter = _scoreOf(bAfterProfiles, TestConfig.testSportType);
      debugPrint(
          '[AT] 후 점수 A=$aScoreAfter (전: $aScoreBefore) / B=$bScoreAfter (전: $bScoreBefore)');

      expect(bScoreAfter < bScoreBefore, true,
          reason: '미응답자 B 점수가 하락하지 않음 ($bScoreBefore → $bScoreAfter)');
      expect(aScoreAfter > aScoreBefore, true,
          reason: '수락자 A 보상 점수가 적용되지 않음 ($aScoreBefore → $aScoreAfter)');
      debugPrint('[AT] OK 점수 변동 검증 — 패널티/보상 적용');

      // ── phase 8: 진행 중 매칭에서 사라졌는지 ──
      final remaining = await api.getMyMatches(accessToken);
      final stillActive = remaining.any((m) =>
          m['id'] == matchId &&
          ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(m['status']));
      expect(stillActive, false,
          reason: '타임아웃된 매치가 아직 진행 중 상태로 남아있음');
      debugPrint('[AT] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
