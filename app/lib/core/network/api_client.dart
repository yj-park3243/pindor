import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';
import '../storage/secure_storage.dart';
import '../network/socket_service.dart';

/// Dio 기반 API 클라이언트
/// - 토큰 자동 첨부 인터셉터
/// - 401 발생 시 자동 토큰 갱신
/// - 표준 에러 응답 파싱
class ApiClient {
  ApiClient._();

  static final ApiClient _instance = ApiClient._();
  static ApiClient get instance => _instance;

  late final Dio _dio;
  final SecureStorage _storage = SecureStorage.instance;
  bool _isRefreshing = false;

  void initialize() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_storage, _dio, this),
      if (kDebugMode) _LoggingInterceptor(),
    ]);
  }

  Dio get dio => _dio;

  // ─── GET 요청 ───
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  // ─── POST 요청 ───
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: body,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  // ─── PATCH 요청 ───
  Future<dynamic> patch(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.patch(
        path,
        data: body,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  // ─── DELETE 요청 ───
  Future<dynamic> delete(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: body,
        queryParameters: queryParameters,
        options: options,
      );
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  // ─── 멀티파트 업로드 ───
  Future<dynamic> uploadMultipart(
    String path,
    FormData formData, {
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
        onSendProgress: onSendProgress,
      );
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}

/// 인증 인터셉터: 요청에 토큰 첨부, 401 시 자동 갱신
class _AuthInterceptor extends Interceptor {
  final SecureStorage _storage;
  final Dio _dio;
  final ApiClient _client;

  _AuthInterceptor(this._storage, this._dio, this._client);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 토큰 불필요한 엔드포인트 제외
    final skipAuth = [
      '/auth/kakao',
      '/auth/google',
      '/auth/apple',
      '/auth/refresh',
      '/auth/email/login',
      '/auth/email/register',
      '/app-version',
      '/notices',
    ];
    if (skipAuth.any((path) => options.path.contains(path))) {
      return handler.next(options);
    }

    final token = await _storage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_client._isRefreshing) {
      _client._isRefreshing = true;

      try {
        final refreshToken = await _storage.getRefreshToken();
        if (refreshToken == null) {
          await _storage.clearTokens();
          return handler.next(err);
        }

        // 토큰 갱신 요청
        final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
        final response = await refreshDio.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );

        final newAccessToken = response.data['data']['accessToken'] as String;
        final newRefreshToken = response.data['data']['refreshToken'] as String?;

        await _storage.saveAccessToken(newAccessToken);
        if (newRefreshToken != null) {
          await _storage.saveRefreshToken(newRefreshToken);
        }

        // 소켓 재연결
        SocketService.instance.connect(newAccessToken);

        // 원래 요청 재시도
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
        final retryResponse = await _dio.fetch(err.requestOptions);
        return handler.resolve(retryResponse);
      } catch (e) {
        await _storage.clearTokens();
        handler.next(err);
      } finally {
        _client._isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
}

/// 디버그 로깅 인터셉터
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint(
        '[API] ${options.method} ${options.baseUrl}${options.path}');
    if (options.data != null) {
      debugPrint('[API] Body: ${options.data}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('[API] ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
        '[API] Error: ${err.response?.statusCode} ${err.requestOptions.path}');
    debugPrint('[API] Error data: ${err.response?.data}');
    handler.next(err);
  }
}

/// API 에러 파싱 유틸리티
class ApiException implements Exception {
  final String code;
  final String message;
  final dynamic details;
  final int? statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.details,
    this.statusCode,
  });

  factory ApiException.fromDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['error'] != null) {
      final errorData = data['error'] as Map<String, dynamic>;
      return ApiException(
        code: errorData['code']?.toString() ?? 'UNKNOWN',
        message: errorData['message']?.toString() ?? '알 수 없는 오류가 발생했습니다.',
        details: errorData['details'],
        statusCode: error.response?.statusCode,
      );
    }

    // 네트워크 에러
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        code: 'TIMEOUT',
        message: '요청 시간이 초과되었습니다. 인터넷 연결을 확인해주세요.',
      );
    }

    if (error.type == DioExceptionType.connectionError) {
      return const ApiException(
        code: 'NETWORK_ERROR',
        message: '인터넷에 연결할 수 없습니다.',
      );
    }

    return ApiException(
      code: 'SERVER_ERROR',
      message: '서버 오류가 발생했습니다.',
      statusCode: error.response?.statusCode,
    );
  }

  @override
  String toString() => 'ApiException($code): $message';
}
