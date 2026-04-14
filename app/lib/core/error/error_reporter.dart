import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';
import '../storage/secure_storage.dart';

/// 앱 에러 리포터 싱글톤
/// - 에러를 서버로 즉시 전송
/// - 5분 내 동일 에러 중복 전송 방지
/// - 에러 리포팅 자체가 추가 에러를 내지 않도록 모든 곳에 try-catch
class ErrorReporter {
  ErrorReporter._();

  static final ErrorReporter _instance = ErrorReporter._();
  static ErrorReporter get instance => _instance;

  // 중복 전송 방지: errorKey → 마지막 전송 시각
  final Map<String, DateTime> _recentErrors = {};
  static const Duration _deduplicateWindow = Duration(minutes: 5);
  static const int _maxDeduplicateEntries = 200;

  late final Dio _dio;

  void initialize() {
    try {
      _dio = Dio(BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));
    } catch (e) {
      debugPrint('[ErrorReporter] initialize failed: $e');
    }
  }

  /// 에러를 서버로 전송
  /// [error] — 발생한 에러 객체
  /// [stackTrace] — 스택 트레이스 (nullable)
  /// [screenName] — 에러가 발생한 화면 이름 (nullable)
  Future<void> reportError(
    dynamic error,
    StackTrace? stackTrace, {
    String? screenName,
  }) async {
    try {
      final errorMessage = _extractMessage(error);
      final stackTraceStr = stackTrace?.toString();

      // 중복 에러 체크 (5분 내 동일 에러 스킵)
      final dedupeKey = _makeDedupeKey(errorMessage, screenName);
      if (_isDuplicate(dedupeKey)) {
        return;
      }
      _recordSent(dedupeKey);

      final deviceInfo = _collectDeviceInfo();

      final body = <String, dynamic>{
        'errorMessage': errorMessage,
        if (stackTraceStr != null && stackTraceStr.isNotEmpty)
          'stackTrace': stackTraceStr.length > 20000
              ? stackTraceStr.substring(0, 20000)
              : stackTraceStr,
        'deviceInfo': deviceInfo,
        if (screenName != null && screenName.isNotEmpty) 'screenName': screenName,
      };

      // 토큰이 있으면 Authorization 헤더 첨부 (선택적 인증)
      final options = await _buildRequestOptions();

      await _dio.post('/error-logs', data: body, options: options);
    } catch (e) {
      // 에러 리포팅 실패는 조용히 무시 — 앱 동작에 영향 없음
      debugPrint('[ErrorReporter] Failed to report error: $e');
    }
  }

  // ─── 내부 헬퍼 ────────────────────────────────────────────────────────────

  String _extractMessage(dynamic error) {
    try {
      if (error == null) return 'Unknown error';
      final msg = error.toString();
      // 너무 길면 자름
      return msg.length > 5000 ? msg.substring(0, 5000) : msg;
    } catch (_) {
      return 'Unknown error';
    }
  }

  String _makeDedupeKey(String errorMessage, String? screenName) {
    // 첫 200자 + 화면명으로 키 생성
    final prefix = errorMessage.length > 200
        ? errorMessage.substring(0, 200)
        : errorMessage;
    return '${screenName ?? ''}::$prefix';
  }

  bool _isDuplicate(String key) {
    try {
      final lastSent = _recentErrors[key];
      if (lastSent == null) return false;
      return DateTime.now().difference(lastSent) < _deduplicateWindow;
    } catch (_) {
      return false;
    }
  }

  void _recordSent(String key) {
    try {
      // 항목 수 제한 (메모리 누수 방지)
      if (_recentErrors.length >= _maxDeduplicateEntries) {
        final oldest = _recentErrors.entries
            .reduce((a, b) => a.value.isBefore(b.value) ? a : b);
        _recentErrors.remove(oldest.key);
      }
      _recentErrors[key] = DateTime.now();
    } catch (_) {
      // 무시
    }
  }

  Map<String, dynamic> _collectDeviceInfo() {
    try {
      return {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'isDebug': kDebugMode,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Options?> _buildRequestOptions() async {
    try {
      final token = await SecureStorage.instance.getAccessToken();
      if (token == null) return null;
      return Options(headers: {'Authorization': 'Bearer $token'});
    } catch (_) {
      return null;
    }
  }
}
