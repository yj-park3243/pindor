import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'test_config.dart';

/// E2E 테스트용 서버 API 헬퍼
///
/// - 앱의 ApiClient와 독립된 Dio 인스턴스를 사용 (토큰 인터셉터 없음)
/// - Authorization 헤더를 수동으로 관리
/// - 테스트 계정 생성, 매칭 조작, 정리 등 API를 직접 호출
class ApiHelper {
  late final Dio _dio;

  ApiHelper() {
    _dio = Dio(BaseOptions(
      baseUrl: TestConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(_TestLogInterceptor());
    }
  }

  // ─── 인증 ───────────────────────────────────────────────────

  /// 이메일 회원가입 → accessToken 반환
  Future<String> register(String email, String password) async {
    final response = await _dio.post(
      '/auth/email/register',
      data: {'email': email, 'password': password},
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return data['accessToken'] as String;
  }

  /// 이메일 로그인 → accessToken 반환
  Future<String> login(String email, String password) async {
    final response = await _dio.post(
      '/auth/email/login',
      data: {'email': email, 'password': password},
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return data['accessToken'] as String;
  }

  /// 로그인 응답 전체 반환 (accessToken + refreshToken + user)
  Future<Map<String, dynamic>> loginFull(
      String email, String password) async {
    final response = await _dio.post(
      '/auth/email/login',
      data: {'email': email, 'password': password},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 회원가입 응답 전체 반환
  Future<Map<String, dynamic>> registerFull(
      String email, String password) async {
    final response = await _dio.post(
      '/auth/email/register',
      data: {'email': email, 'password': password},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  // ─── 사용자 ─────────────────────────────────────────────────

  /// 내 정보 조회
  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await _dio.get(
      '/users/me',
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 닉네임 업데이트
  Future<Map<String, dynamic>> updateProfile(
    String token, {
    required String nickname,
  }) async {
    final response = await _dio.patch(
      '/users/me',
      data: {'nickname': nickname},
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 위치 설정
  Future<void> setLocation(
    String token, {
    required double latitude,
    required double longitude,
    required String address,
    int matchRadiusKm = 10,
  }) async {
    await _dio.post(
      '/users/me/location',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'matchRadiusKm': matchRadiusKm,
      },
      options: _authOptions(token),
    );
  }

  /// 계정 삭제 (테스트 cleanup용)
  Future<void> deleteUser(String token) async {
    await _dio.delete(
      '/users/me',
      data: {'reason': 'E2E 테스트 계정 정리'},
      options: _authOptions(token),
    );
  }

  // ─── 스포츠 프로필 ──────────────────────────────────────────

  /// 스포츠 프로필 생성
  Future<Map<String, dynamic>> createSportsProfile(
    String token, {
    required String sportType,
    required String displayName,
    double? gHandicap,
  }) async {
    final response = await _dio.post(
      '/sports-profiles',
      data: {
        'sportType': sportType,
        'displayName': displayName,
        if (gHandicap != null) 'gHandicap': gHandicap,
      },
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  // ─── 핀 ─────────────────────────────────────────────────────

  /// 전체 핀 목록 조회 (핀 ID 얻기용)
  Future<List<Map<String, dynamic>>> getAllPins(String token) async {
    final response = await _dio.get(
      '/pins/all',
      options: _authOptions(token),
    );
    final data = response.data['data'] as List<dynamic>?;
    if (data == null) return [];
    return data.cast<Map<String, dynamic>>();
  }

  // ─── 매칭 ────────────────────────────────────────────────────

  /// 매칭 요청 생성
  Future<Map<String, dynamic>> createMatchRequest(
    String token, {
    required String sportType,
    required String pinId,
    String? message,
    String? genderPreference,
    int? minAge,
    int? maxAge,
    int minOpponentScore = 100,
    int maxOpponentScore = 3000,
  }) async {
    final response = await _dio.post(
      '/matches/requests',
      data: {
        'sportType': sportType,
        'pinId': pinId,
        'minOpponentScore': minOpponentScore,
        'maxOpponentScore': maxOpponentScore,
        if (message != null) 'message': message,
        if (genderPreference != null) 'genderPreference': genderPreference,
        if (minAge != null) 'minAge': minAge,
        if (maxAge != null) 'maxAge': maxAge,
      },
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 내 매칭 목록 조회
  Future<List<Map<String, dynamic>>> getMyMatches(
    String token, {
    String? status,
  }) async {
    final response = await _dio.get(
      '/matches',
      queryParameters: {
        if (status != null) 'status': status,
      },
      options: _authOptions(token),
    );
    final data = response.data['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// 매칭 상태 조회 (폴링용)
  Future<Map<String, dynamic>> getMatchStatus(
      String token, String matchId) async {
    final response = await _dio.get(
      '/matches/$matchId/status',
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 매칭 상세 조회
  Future<Map<String, dynamic>> getMatchDetail(
      String token, String matchId) async {
    final response = await _dio.get(
      '/matches/$matchId',
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 매칭 수락
  Future<Map<String, dynamic>> acceptMatch(
      String token, String matchId) async {
    final response = await _dio.post(
      '/matches/$matchId/accept',
      data: {},
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 경기 확정 (날짜/장소 입력)
  Future<Map<String, dynamic>> confirmMatch(
    String token,
    String matchId, {
    required String scheduledDate,
    required String scheduledTime,
    required String venueName,
    double? venueLatitude,
    double? venueLongitude,
  }) async {
    final response = await _dio.patch(
      '/matches/$matchId/confirm',
      data: {
        'scheduledDate': scheduledDate,
        'scheduledTime': scheduledTime,
        'venueName': venueName,
        if (venueLatitude != null) 'venueLatitude': venueLatitude,
        if (venueLongitude != null) 'venueLongitude': venueLongitude,
      },
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  // ─── 채팅 ────────────────────────────────────────────────────

  /// 메시지 전송 (HTTP 폴백)
  Future<Map<String, dynamic>> sendMessage(
    String token,
    String roomId, {
    required String content,
    String messageType = 'TEXT',
  }) async {
    final response = await _dio.post(
      '/chat-rooms/$roomId/messages',
      data: {'messageType': messageType, 'content': content},
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  /// 채팅방 목록 조회
  Future<List<Map<String, dynamic>>> getChatRooms(String token) async {
    final response = await _dio.get(
      '/chat-rooms',
      options: _authOptions(token),
    );
    final data = response.data['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  // ─── 경기 결과 ───────────────────────────────────────────────

  /// 경기 결과 입력
  Future<void> submitGameResult(
    String token,
    String gameId, {
    required int myScore,
    required int opponentScore,
    required String winnerId,
  }) async {
    await _dio.post(
      '/games/$gameId/result',
      data: {
        'myScore': myScore,
        'opponentScore': opponentScore,
        'winnerId': winnerId,
      },
      options: _authOptions(token),
    );
  }

  /// 결과 확인/거절
  Future<Map<String, dynamic>?> confirmGameResult(
    String token,
    String gameId, {
    required bool isConfirmed,
    String? comment,
  }) async {
    final response = await _dio.post(
      '/games/$gameId/confirm',
      data: {
        'isConfirmed': isConfirmed,
        if (comment != null) 'comment': comment,
      },
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>?;
  }

  /// 경기 상세 조회
  Future<Map<String, dynamic>> getGameDetail(
      String token, String gameId) async {
    final response = await _dio.get(
      '/games/$gameId',
      options: _authOptions(token),
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  // ─── 폴링 유틸리티 ──────────────────────────────────────────

  /// 특정 조건이 충족될 때까지 폴링
  ///
  /// [fetcher]: 매번 호출할 API 함수
  /// [condition]: 반환된 데이터가 조건을 만족하는지 확인
  /// [interval]: 폴링 간격 (기본 3초)
  /// [maxAttempts]: 최대 시도 횟수 (기본 60회 = 3분)
  Future<T> pollUntil<T>({
    required Future<T> Function() fetcher,
    required bool Function(T) condition,
    Duration interval = TestConfig.pollInterval,
    int maxAttempts = TestConfig.maxPollAttempts,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final result = await fetcher();
        if (condition(result)) return result;
      } catch (e) {
        debugPrint('[Poll] 시도 ${i + 1}/$maxAttempts 실패: $e');
      }
      if (i < maxAttempts - 1) {
        await Future.delayed(interval);
      }
    }
    throw TimeoutException(
      '폴링 조건이 ${maxAttempts * interval.inSeconds}초 내에 충족되지 않았습니다.',
    );
  }

  /// 매칭 상태가 특정 값이 될 때까지 폴링
  Future<Map<String, dynamic>> pollMatchStatus(
    String token,
    String matchId, {
    required String expectedStatus,
  }) async {
    return pollUntil(
      fetcher: () => getMatchStatus(token, matchId),
      condition: (data) => data['status'] == expectedStatus,
    );
  }

  /// 내 매칭 목록에서 특정 상태의 매칭이 생길 때까지 폴링
  Future<Map<String, dynamic>> pollForMatch(
    String token, {
    required String expectedStatus,
  }) async {
    return pollUntil<Map<String, dynamic>>(
      fetcher: () async {
        final matches = await getMyMatches(token, status: expectedStatus);
        if (matches.isEmpty) {
          throw const _PollNotReadyException('매칭 없음');
        }
        return matches.first;
      },
      condition: (data) => data['status'] == expectedStatus,
    );
  }

  // ─── 내부 헬퍼 ──────────────────────────────────────────────

  Options _authOptions(String token) {
    return Options(headers: {'Authorization': 'Bearer $token'});
  }
}

/// 폴링 미완료 상태를 표시하는 내부 예외
class _PollNotReadyException implements Exception {
  final String message;
  const _PollNotReadyException(this.message);
}

/// 폴링 타임아웃 예외
class TimeoutException implements Exception {
  final String message;
  const TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}

/// 테스트용 로깅 인터셉터
class _TestLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[E2E API] --> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint(
        '[E2E API] <-- ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
        '[E2E API] ERR ${err.response?.statusCode} ${err.requestOptions.path}: '
        '${err.response?.data}');
    handler.next(err);
  }
}
