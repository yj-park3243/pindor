import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import 'local_notification_service.dart';
import '../../core/network/socket_service.dart';

/// FCM 푸시 알림 서비스 (PRD 4.10.9 기반)
/// - 초기화 및 권한 요청
/// - 토큰 등록/갱신
/// - 딥링크 처리
/// - 포그라운드 메시지 핸들링
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService _instance =
      PushNotificationService._();
  static PushNotificationService get instance => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SecureStorage _storage = SecureStorage.instance;

  // Firebase 리스너 구독 관리
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  // 딥링크 처리 콜백 (앱 라우터에서 설정)
  void Function(String deepLink)? onDeepLink;

  /// 초기화 (main.dart에서 Firebase.initializeApp() 후 호출)
  Future<void> initialize() async {
    try {
      await _initializeInternal();
    } catch (e) {
      debugPrint('[Push] 초기화 실패 (시뮬레이터에서 정상): $e');
    }
  }

  Future<void> _initializeInternal() async {
    // Android 13+ 런타임 알림 권한 요청
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      debugPrint('[Push] Android 알림 권한 상태: $status');
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('[Push] Android 알림 권한 거부됨 — FCM 초기화는 계속 진행');
      }
    }

    // iOS 권한 요청
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('[Push] 권한 상태: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[Push] 푸시 알림 권한 거부됨 — FCM 초기화는 계속 진행');
    }

    // iOS: APNS 토큰이 준비될 때까지 대기 후 FCM 토큰 요청
    if (Platform.isIOS) {
      String? apnsToken;
      for (var i = 0; i < 5; i++) {
        apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      debugPrint('[Push] APNS 토큰: ${apnsToken != null ? "준비됨" : "없음"}');
    }

    // FCM 토큰 등록 (시뮬레이터에서는 실패 가능)
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } catch (e) {
      debugPrint('[Push] FCM 토큰 가져오기 실패 (시뮬레이터): $e');
    }

    // 토큰 갱신 감지
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_registerToken);

    // 포그라운드 메시지 핸들러
    _onMessageSub?.cancel();
    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[Push] 포그라운드 메시지: ${message.notification?.title}');

      // MATCH_PENDING_ACCEPT는 소켓 상태와 관계없이 딥링크 처리 (소켓 유실 대비)
      final type = message.data['type'] as String?;
      if (type == 'MATCH_PENDING_ACCEPT') {
        _handleDeepLink(message);
        return;
      }

      // 기타 알림: 소켓이 끊겼을 때만 로컬 알림 표시
      if (!SocketService.instance.isConnected) {
        LocalNotificationService.instance.showFromRemoteMessage(message);
      }
    });

    // 백그라운드/종료 상태에서 알림 탭 → 딥링크 처리
    _onMessageOpenedSub?.cancel();
    _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleDeepLink);

    // 앱이 종료 상태에서 알림 탭으로 실행된 경우
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // 앱 초기화 완료 후 처리되도록 지연
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleDeepLink(initialMessage);
      });
    }
  }

  /// FCM 토큰을 서버에 등록 (최대 3회 재시도, exponential backoff)
  Future<void> _registerToken(String token) async {
    // 이전 토큰과 동일하면 스킵
    final savedToken = await _storage.getFcmToken();
    if (savedToken == token) return;

    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await ApiClient.instance.post(
          '/devices/push-token',
          body: {
            'token': token,
            'platform': Platform.isIOS ? 'IOS' : 'ANDROID',
          },
        );

        await _storage.saveFcmToken(token);
        debugPrint('[Push] FCM 토큰 등록 완료');
        return;
      } catch (e) {
        debugPrint('[Push] FCM 토큰 등록 실패 (시도 ${attempt + 1}/$maxRetries): $e');
        if (attempt < maxRetries - 1) {
          // exponential backoff: 1초 → 2초 → 4초
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
  }

  /// 서버에서 토큰 해제 (로그아웃 시)
  Future<void> unregisterToken() async {
    try {
      final token = await _storage.getFcmToken();
      if (token == null) return;

      await ApiClient.instance.delete(
        '/devices/push-token',
        body: {'token': token},
      );

      debugPrint('[Push] FCM 토큰 해제 완료');
    } catch (e) {
      debugPrint('[Push] FCM 토큰 해제 실패: $e');
    }
  }

  /// 딥링크 처리
  void _handleDeepLink(RemoteMessage message) {
    final deepLink = message.data['deepLink'] as String?;
    if (deepLink != null && onDeepLink != null) {
      debugPrint('[Push] 딥링크 처리: $deepLink');
      try {
        onDeepLink!(deepLink);
      } catch (e) {
        debugPrint('[Push] 딥링크 처리 실패: $e');
      }
    }
  }

  /// 백그라운드 메시지 핸들러 (최상위 함수로 등록 필요)
  static Future<void> backgroundMessageHandler(RemoteMessage message) async {
    debugPrint('[Push] 백그라운드 메시지: ${message.notification?.title}');
    // 백그라운드에서는 Firebase가 자동으로 알림 표시
  }
}
