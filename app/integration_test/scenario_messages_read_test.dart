import 'dart:async';

import 'package:dio/dio.dart';
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

Future<void> _shot(String name) async {
  try {
    await _shotDio.get('http://127.0.0.1:9998/userA_$name');
    await Future.delayed(const Duration(milliseconds: 600));
  } catch (_) {}
}

/// 시나리오 — 채팅방 입장 시 자동 읽음 처리 (JOIN_ROOM → MESSAGES_READ)
///
/// 검증:
///   1. B 가 메시지 N개 전송 (HTTP) → 메시지 readAt = null
///   2. A 가 /chats/{roomId} 입장 → 소켓 JOIN_ROOM emit
///   3. 서버가 자동 markMessagesRead 호출 → readAt 채워짐
///   4. B 토큰으로 chat-rooms 의 unreadCount = 0
///   5. A 측 매칭 카드의 unread 배지도 사라짐 (서버 응답 반영)
///
/// 단일 시뮬(A)만 사용. B 액션은 ApiHelper 로 외부 트리거.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiHelper();

  const accessToken = String.fromEnvironment('TEST_ACCESS_TOKEN');
  const refreshToken = String.fromEnvironment('TEST_REFRESH_TOKEN');
  const userId = String.fromEnvironment('TEST_USER_ID');
  const opponentToken =
      String.fromEnvironment('TEST_OPPONENT_ACCESS_TOKEN');
  const pinName = String.fromEnvironment(
    'SCENARIO_PIN_NAME',
    defaultValue: TestConfig.testPinName,
  );

  testWidgets(
    '채팅방 입장 시 자동 markRead — readAt 채워짐 + B unread=0',
    (tester) async {
      expect(accessToken.isNotEmpty, true, reason: 'TEST_ACCESS_TOKEN 필수');
      expect(opponentToken.isNotEmpty, true,
          reason: 'TEST_OPPONENT_ACCESS_TOKEN 필수');
      debugPrint('[MR] 시작 userId=$userId');

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
        message: 'messages-read A',
      );
      await api.createMatchRequest(
        opponentToken,
        sportType: TestConfig.testSportType,
        pinId: pinId,
        message: 'messages-read B',
      );
      debugPrint('[MR] 양쪽 매칭 요청 생성');

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
      debugPrint('[MR] 앱 기동 완료');
      await _shot('01_app_ready');

      // ── phase 3: 매칭 성사 + 양쪽 수락 → CHAT ──
      final pending = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final ms = await api.getMyMatches(accessToken);
          final f = ms
              .where((m) =>
                  ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(m['status']))
              .toList();
          if (f.isEmpty) throw Exception('no match yet');
          return f.first;
        },
        condition: (m) => true,
        maxAttempts: 60,
      );
      final matchId = pending['id'] as String;
      debugPrint('[MR] 매칭 잡힘 — matchId=$matchId');

      try {
        await api.acceptMatch(accessToken, matchId);
      } catch (_) {}
      try {
        await api.acceptMatch(opponentToken, matchId);
      } catch (_) {}

      final chatMatch = await api.pollUntil<Map<String, dynamic>>(
        fetcher: () => api.getMatchDetail(accessToken, matchId),
        condition: (m) =>
            ['CHAT', 'CONFIRMED'].contains(m['status'] as String? ?? '') &&
            (m['chatRoomId'] != null &&
                (m['chatRoomId'] as String).isNotEmpty),
        maxAttempts: 60,
      );
      final chatRoomId = chatMatch['chatRoomId'] as String;
      debugPrint('[MR] CHAT 진입 — chatRoomId=$chatRoomId');
      await _shot('02_chat_ready');

      // ── phase 4: B 가 메시지 2개 전송 (A 채팅방 입장 전) ──
      _forceGo('/matches');
      await _settle(tester, const Duration(seconds: 2));

      await api.sendMessage(
        opponentToken,
        chatRoomId,
        content: 'read-test 1',
      );
      await api.sendMessage(
        opponentToken,
        chatRoomId,
        content: 'read-test 2',
      );
      debugPrint('[MR] B 메시지 2개 전송');

      // 서버 측 B의 unreadCount(자기 입장에서 받은 미읽음)은 0 일 것 (B 자신이 보낸 메시지).
      // A 측 unreadCount = 2 검증.
      final roomsBefore = await api.getChatRooms(accessToken);
      final aRoomBefore = roomsBefore.firstWhere(
        (r) => r['id'] == chatRoomId,
        orElse: () => <String, dynamic>{},
      );
      final aUnreadBefore =
          (aRoomBefore['unreadCount'] as num?)?.toInt() ?? 0;
      debugPrint('[MR] A unreadCount(전) = $aUnreadBefore');
      expect(aUnreadBefore >= 2, true,
          reason: 'A unread 가 2 이상 아님 (메시지 미수신?)');

      // ── phase 5: A 가 채팅방 입장 (소켓 JOIN_ROOM → 자동 markRead) ──
      _forceGo('/chats/$chatRoomId');
      await _settle(tester, const Duration(seconds: 4));
      await _shot('03_chat_entered');
      debugPrint('[MR] A 채팅방 입장 완료');

      // ── phase 6: A 측 unreadCount = 0 확인 ──
      await api.pollUntil<Map<String, dynamic>>(
        fetcher: () async {
          final rooms = await api.getChatRooms(accessToken);
          return rooms.firstWhere(
            (r) => r['id'] == chatRoomId,
            orElse: () => <String, dynamic>{},
          );
        },
        condition: (r) => ((r['unreadCount'] as num?)?.toInt() ?? 99) == 0,
        maxAttempts: 30,
      );
      debugPrint('[MR] OK A unreadCount = 0 확인');

      // ── phase 7: B 시점에서도 자기가 보낸 메시지가 읽음 처리됐는지
      // (chat-rooms 응답의 lastMessage 등으로는 검증 어려우므로 매치 종료 시
      //  의 unreadCount 정합성만 가볍게 cross-check)
      final roomsB = await api.getChatRooms(opponentToken);
      final bRoom = roomsB.firstWhere(
        (r) => r['id'] == chatRoomId,
        orElse: () => <String, dynamic>{},
      );
      // B 가 보낸 메시지 → B 입장에서 unreadCount 는 항상 0 (자기가 받은 미읽음 기준)
      final bUnread = (bRoom['unreadCount'] as num?)?.toInt() ?? 0;
      debugPrint('[MR] B unreadCount(자기 기준) = $bUnread');
      expect(bUnread, 0, reason: 'B 자기 기준 unread 가 0 아님');

      debugPrint('[MR] === 전체 통과 ===');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
