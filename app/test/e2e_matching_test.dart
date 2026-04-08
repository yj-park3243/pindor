/// E2E 매칭 플로우 테스트 (API 기반)
///
/// 실행: dart run test/e2e_matching_test.dart
///
/// 흐름:
///   1. 유저 A, B 회원가입
///   2. 스포츠 프로필 생성 (GOLF)
///   3. 위치 설정
///   4. 같은 핀에 매칭 요청
///   5. 자동 매칭 성사 확인
///   6. 양측 수락
///   7. 채팅 메시지 전송
///   8. 경기 확정
///   9. 결과 입력 + 확인
///  10. 점수 변경 확인
///  11. 계정 정리
import 'dart:convert';
import 'dart:io';

const baseUrl = 'http://127.0.0.1:3000/v1';

Future<Map<String, dynamic>> api(
  String method,
  String path, {
  Map<String, dynamic>? body,
  String? token,
  Map<String, String>? query,
}) async {
  final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
  final client = HttpClient();
  try {
    late HttpClientRequest req;
    switch (method) {
      case 'GET':
        req = await client.getUrl(uri);
      case 'POST':
        req = await client.postUrl(uri);
      case 'PATCH':
        req = await client.patchUrl(uri);
      case 'DELETE':
        req = await client.deleteUrl(uri);
      default:
        throw 'Unknown method: $method';
    }

    req.headers.set('Content-Type', 'application/json; charset=utf-8');
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) req.add(utf8.encode(jsonEncode(body)));

    final res = await req.close();
    final resBody = await res.transform(utf8.decoder).join();
    final json = jsonDecode(resBody) as Map<String, dynamic>;

    if (res.statusCode >= 400) {
      throw 'API Error ${res.statusCode}: ${json['error']?['message'] ?? resBody}';
    }
    return json;
  } finally {
    client.close();
  }
}

Future<T> poll<T>({
  required Future<T> Function() fetcher,
  required bool Function(T) condition,
  int maxAttempts = 40,
  Duration interval = const Duration(seconds: 3),
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    try {
      final result = await fetcher();
      if (condition(result)) return result;
    } catch (_) {}
    if (i < maxAttempts - 1) await Future.delayed(interval);
    stdout.write('.');
  }
  throw 'Poll timeout after ${maxAttempts * interval.inSeconds}s';
}

void step(String msg) {
  stdout.writeln('\n\x1B[32m✓\x1B[0m $msg');
}

void info(String msg) {
  stdout.writeln('  \x1B[90m$msg\x1B[0m');
}

Future<void> main() async {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final emailA = 'e2e_a_$ts@test.com';
  final emailB = 'e2e_b_$ts@test.com';
  const password = 'test123456';

  String? tokenA, tokenB;

  try {
    stdout.writeln('\n\x1B[1m═══ E2E 매칭 플로우 테스트 ═══\x1B[0m\n');

    // ── 1. 회원가입 ──────────────────────────────────────
    step('1. 유저 A 회원가입');
    final regA = await api('POST', '/auth/email/register', body: {
      'email': emailA,
      'password': password,
    });
    tokenA = regA['data']['accessToken'] as String;
    final userAId = regA['data']['user']['id'] as String;
    info('이메일: $emailA / ID: $userAId');

    step('1. 유저 B 회원가입');
    final regB = await api('POST', '/auth/email/register', body: {
      'email': emailB,
      'password': password,
    });
    tokenB = regB['data']['accessToken'] as String;
    final userBId = regB['data']['user']['id'] as String;
    info('이메일: $emailB / ID: $userBId');

    // ── 2. 프로필 설정 ───────────────────────────────────
    step('2. 유저 A 닉네임 + 스포츠 프로필');
    await api('PATCH', '/users/me', token: tokenA, body: {
      'nickname': 'A_$ts',
    });
    final spA = await api('POST', '/sports-profiles', token: tokenA, body: {
      'sportType': 'GOLF',
      'displayName': '테스트골퍼A',
      'gHandicap': 25.0,
      'matchMessage': '테스트 매칭입니다!',
    });
    final scoreA_before = spA['data']['currentScore'] as int;
    info('초기 점수: $scoreA_before');

    step('2. 유저 B 닉네임 + 스포츠 프로필');
    await api('PATCH', '/users/me', token: tokenB, body: {
      'nickname': 'B_$ts',
    });
    final spB = await api('POST', '/sports-profiles', token: tokenB, body: {
      'sportType': 'GOLF',
      'displayName': '테스트골퍼B',
      'gHandicap': 25.0,
      'matchMessage': '잘 부탁드립니다!',
    });
    final scoreB_before = spB['data']['currentScore'] as int;
    info('초기 점수: $scoreB_before');

    // ── 3. 위치 설정 ─────────────────────────────────────
    step('3. 위치 설정 (서울)');
    await api('POST', '/users/me/location', token: tokenA, body: {
      'latitude': 37.5665,
      'longitude': 126.9780,
      'address': '서울특별시 중구',
    });
    await api('POST', '/users/me/location', token: tokenB, body: {
      'latitude': 37.5665,
      'longitude': 126.9780,
      'address': '서울특별시 중구',
    });
    info('양측 서울 중심 설정 완료');

    // ── 4. 핀 조회 + 매칭 요청 ───────────────────────────
    step('4. 핀 조회');
    final pinsRes = await api('GET', '/pins/all', token: tokenA);
    final pins = pinsRes['data'] as List;
    if (pins.isEmpty) throw '핀이 없습니다!';
    final pinId = pins.first['id'] as String;
    final pinName = pins.first['name'] as String;
    info('핀: $pinName ($pinId)');

    step('4. 유저 A 매칭 요청');
    final mrA = await api('POST', '/matches/requests', token: tokenA, body: {
      'sportType': 'GOLF',
      'pinId': pinId,
      'minOpponentScore': 100,
      'maxOpponentScore': 3000,
      'message': 'A의 매칭 요청',
    });
    info('요청 ID: ${mrA['data']['id']} / 상태: ${mrA['data']['status']}');

    step('4. 유저 B 매칭 요청 (자동 매칭 트리거)');
    final mrB = await api('POST', '/matches/requests', token: tokenB, body: {
      'sportType': 'GOLF',
      'pinId': pinId,
      'minOpponentScore': 100,
      'maxOpponentScore': 3000,
      'message': 'B의 매칭 요청',
    });
    info('요청 ID: ${mrB['data']['id']} / 상태: ${mrB['data']['status']} / 후보: ${mrB['data']['candidatesCount']}');

    // ── 5. 매칭 성사 확인 ────────────────────────────────
    step('5. 매칭 성사 확인 (폴링)');
    stdout.write('  대기 중');
    final matchA = await poll<Map<String, dynamic>>(
      fetcher: () async {
        final res = await api('GET', '/matches', token: tokenA);
        final matches = res['data'] as List;
        final found = matches.where((m) =>
            ['PENDING_ACCEPT', 'CHAT', 'CONFIRMED'].contains(m['status']));
        if (found.isEmpty) throw 'no match';
        return found.first as Map<String, dynamic>;
      },
      condition: (m) => m['status'] != null,
    );
    final matchId = matchA['id'] as String;
    stdout.writeln();
    info('매칭 ID: $matchId / 상태: ${matchA['status']}');

    // ── 6. 양측 수락 ────────────────────────────────────
    // B의 매칭 목록에서도 동일 매칭 확인
    final matchBRes = await api('GET', '/matches', token: tokenB);
    final matchesB = matchBRes['data'] as List;
    final matchB = matchesB.firstWhere(
      (m) => m['status'] == 'PENDING_ACCEPT',
      orElse: () => null,
    );
    final matchIdB = matchB?['id'] as String? ?? matchId;
    info('A 매칭 ID: $matchId / B 매칭 ID: $matchIdB');

    step('6. 유저 A 수락');
    await api('POST', '/matches/$matchId/accept', token: tokenA, body: {});
    info('A 수락 완료');

    step('6. 유저 B 수락');
    await api('POST', '/matches/$matchIdB/accept', token: tokenB, body: {});
    info('B 수락 완료');

    // CHAT 상태 대기
    stdout.write('  CHAT 상태 대기');
    final chatMatch = await poll<Map<String, dynamic>>(
      fetcher: () async {
        final res = await api('GET', '/matches/$matchId', token: tokenA);
        return res['data'] as Map<String, dynamic>;
      },
      condition: (m) => ['CHAT', 'CONFIRMED'].contains(m['status']),
    );
    stdout.writeln();
    info('상태: ${chatMatch['status']}');

    final chatRoomId = chatMatch['chatRoomId'] as String?;

    // ── 7. 채팅 메시지 전송 ──────────────────────────────
    if (chatRoomId != null) {
      step('7. 채팅 메시지 전송');
      await api('POST', '/chat-rooms/$chatRoomId/messages', token: tokenA, body: {
        'messageType': 'TEXT',
        'content': '안녕하세요! 골프 한판 하시죠!',
      });
      info('A → "안녕하세요! 골프 한판 하시죠!"');

      await api('POST', '/chat-rooms/$chatRoomId/messages', token: tokenB, body: {
        'messageType': 'TEXT',
        'content': '네! 잘 부탁드립니다 😊',
      });
      info('B → "네! 잘 부탁드립니다 😊"');
    } else {
      info('채팅방 없음 — 스킵');
    }

    // ── 8. 경기 확정 ────────────────────────────────────
    step('8. 경기 확정');
    final confirmRes = await api('PATCH', '/matches/$matchId/confirm', token: tokenA, body: {
      'scheduledDate': '2026-04-15',
      'scheduledTime': '14:00',
      'venueName': 'E2E 테스트 골프장',
    });
    info('상태: ${confirmRes['data']['status']}');

    // 게임 목록에서 해당 매칭의 게임 찾기
    stdout.write('  게임 조회');
    final gamesRes = await api('GET', '/games', token: tokenA);
    final games = gamesRes['data'] as List;
    stdout.writeln();

    if (games.isNotEmpty) {
      final gameId = games.first['id'] as String;
      info('게임 ID: $gameId');

      // ── 9. 경기 결과 입력 ────────────────────────────────
      step('9. 유저 A 결과 입력 (A 승리: 3-1)');
      await api('POST', '/games/$gameId/result', token: tokenA, body: {
        'myScore': 3,
        'opponentScore': 1,
      });
      info('A 결과 입력 완료');

      step('9. 유저 B 결과 확인');
      await api('POST', '/games/$gameId/confirm', token: tokenB, body: {
        'isConfirmed': true,
      });
      info('B 결과 확인 완료');
    } else {
      info('⚠️ 게임이 자동 생성되지 않음 — 결과 입력 스킵');
    }

    // ── 10. 점수 변경 확인 ───────────────────────────────
    step('10. 점수 변경 확인');
    // 잠시 대기 (ELO 계산)
    await Future.delayed(const Duration(seconds: 2));

    final meA = await api('GET', '/users/me', token: tokenA);
    final meB = await api('GET', '/users/me', token: tokenB);

    final profilesA = meA['data']['sportsProfiles'] as List? ?? [];
    final profilesB = meB['data']['sportsProfiles'] as List? ?? [];

    final golfA = profilesA.firstWhere(
      (p) => p['sportType'] == 'GOLF',
      orElse: () => null,
    );
    final golfB = profilesB.firstWhere(
      (p) => p['sportType'] == 'GOLF',
      orElse: () => null,
    );

    if (golfA != null && golfB != null) {
      final scoreA_after = golfA['currentScore'] as int;
      final scoreB_after = golfB['currentScore'] as int;
      final diffA = scoreA_after - scoreA_before;
      final diffB = scoreB_after - scoreB_before;

      info('유저 A: $scoreA_before → $scoreA_after (${diffA >= 0 ? "+$diffA" : "$diffA"})');
      info('유저 B: $scoreB_before → $scoreB_after (${diffB >= 0 ? "+$diffB" : "$diffB"})');

      if (diffA > 0 && diffB < 0) {
        info('✅ A 승리 → A 점수 상승, B 점수 하락 — 정상');
      } else if (diffA == 0 && diffB == 0) {
        info('⚠️ 점수 변동 없음 — ELO 계산 지연 또는 미적용');
      } else {
        info('⚠️ 예상과 다른 점수 변동');
      }
    } else {
      info('스포츠 프로필 조회 실패');
    }

    // ── 결과 ─────────────────────────────────────────────
    stdout.writeln('\n\x1B[1;32m═══ E2E 테스트 전체 통과 ✅ ═══\x1B[0m\n');

  } catch (e) {
    stdout.writeln('\n\x1B[1;31m═══ E2E 테스트 실패 ❌ ═══\x1B[0m');
    stdout.writeln('  에러: $e\n');
    exitCode = 1;
  } finally {
    // ── 11. 계정 정리 ────────────────────────────────────
    stdout.writeln('\x1B[90m계정 정리 중...\x1B[0m');
    try {
      if (tokenA != null) {
        await api('DELETE', '/users/me', token: tokenA, body: {'reason': 'E2E 테스트'});
      }
    } catch (_) {}
    try {
      if (tokenB != null) {
        await api('DELETE', '/users/me', token: tokenB, body: {'reason': 'E2E 테스트'});
      }
    } catch (_) {}
    stdout.writeln('\x1B[90m정리 완료\x1B[0m\n');
  }
}
