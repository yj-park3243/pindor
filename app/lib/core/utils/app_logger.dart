import 'package:flutter/foundation.dart';

/// 구조화된 앱 로거
/// - DEBUG 모드에서만 출력
/// - 태그 기반 필터링 가능
/// - 추후 Sentry/Firebase Crashlytics 연동 지점
class AppLogger {
  AppLogger._();

  static void debug(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void info(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] ℹ️ $message');
    }
  }

  static void warning(String tag, String message) {
    debugPrint('[$tag] ⚠️ $message');
  }

  static void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    debugPrint('[$tag] ❌ $message');
    if (error != null) {
      debugPrint('[$tag] Error: $error');
    }
    if (stackTrace != null && kDebugMode) {
      debugPrint('[$tag] StackTrace: $stackTrace');
    }
    // TODO: 추후 Sentry/Firebase Crashlytics 연동
    // if (!kDebugMode) {
    //   Sentry.captureException(error, stackTrace: stackTrace);
    // }
  }

  /// API 호출 로깅 (기존 api_client.dart의 debugPrint 대체용)
  static void api(String method, String url, {int? statusCode, String? error}) {
    if (kDebugMode) {
      if (error != null) {
        debugPrint('[API] ❌ $method $url — $error');
      } else {
        debugPrint('[API] $statusCode $url');
      }
    }
  }

  /// 소켓 이벤트 로깅
  static void socket(String event, [String? detail]) {
    if (kDebugMode) {
      debugPrint('[Socket] $event${detail != null ? ' — $detail' : ''}');
    }
  }
}
