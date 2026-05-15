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
    // E2E 테스트 모드 — 알림 권한 시스템 다이얼로그가 시뮬레이터 UI를 가리지 않도록 권한 요청 자체 스킵
    const isTestMode =
        bool.fromEnvironment('TEST_MODE', defaultValue: false);

    // Android 13+ 런타임 알림 권한 요청
    if (Platform.isAndroid && !isTestMode) {
      final status = await Permission.notification.request();
      debugPrint('[Push] Android 알림 권한 상태: $status');
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('[Push] Android 알림 권한 거부됨 — FCM 초기화는 계속 진행');
      }
    }

    // iOS 권한 요청 (테스트 모드에선 시스템 다이얼로그 안 띄움)
    if (!isTestMode) {
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
    } else {
      debugPrint('[Push] TEST_MODE — 권한 요청 스킵');
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

  /// 캐시된 토큰을 신뢰할 수 있는 TTL — 서버에서 isActive=false 됐어도
  /// 이 기간 안에는 강제 재등록으로 자동 복구된다.
  static const Duration _registerTtl = Duration(days: 7);

  /// FCM 토큰을 서버에 등록 (최대 3회 재시도, exponential backoff)
  ///
  /// [force] 가 true 면 토큰/TTL 캐시 비교를 건너뛰고 무조건 서버에 등록한다.
  /// 실패 시 [SecureStorage.pendingFcmRegister] 플래그를 세워 다음 resume 시 재시도된다.
  Future<void> _registerToken(String token, {bool force = false}) async {
    if (!force) {
      final savedToken = await _storage.getFcmToken();
      final registeredAt = await _storage.getFcmTokenRegisteredAt();
      final isFresh = registeredAt != null &&
          DateTime.now().difference(registeredAt) < _registerTtl;
      // 이전 토큰과 동일 + TTL 안쪽이면 스킵
      if (savedToken != null &&
          savedToken == token &&
          savedToken.isNotEmpty &&
          isFresh) {
        return;
      }
    }

    // 인증 토큰이 없으면 등록 시도 자체를 스킵 (401 + 에러 로그 발생 방지)
    // 로그인 후 reregisterToken()에서 다시 호출됨.
    final accessToken = await _storage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      await _storage.setPendingFcmRegister(true);
      debugPrint('[Push] 미로그인 상태 — FCM 토큰 등록 보류 (로그인 후 재시도)');
      return;
    }

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
        await _storage.setFcmTokenRegisteredAt(DateTime.now());
        await _storage.setPendingFcmRegister(false);
        debugPrint(
            '[Push] FCM 토큰 등록 완료 (platform=${Platform.isIOS ? 'IOS' : 'ANDROID'}, head=${token.substring(0, token.length.clamp(0, 12))}...)');
        return;
      } catch (e) {
        debugPrint('[Push] FCM 토큰 등록 실패 (시도 ${attempt + 1}/$maxRetries): $e');
        if (attempt < maxRetries - 1) {
          // exponential backoff: 1초 → 2초 → 4초
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }

    // 모든 재시도 실패 — 다음 resume 시 재시도 하도록 플래그 저장
    await _storage.setPendingFcmRegister(true);
    debugPrint('[Push] FCM 토큰 등록 영구 실패 — pending 플래그 저장, 다음 resume 시 재시도');
  }

  /// 로그인 성공 후 FCM 토큰 재등록 (인증 토큰 확보 후 호출)
  Future<void> reregisterToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        // 권한 거부/시뮬레이터 등으로 토큰을 못 받은 경우 — 다음 resume 시 재시도
        await _storage.setPendingFcmRegister(true);
        return;
      }
      // _registerToken 의 재시도/플래그 처리 로직 재사용
      await _registerToken(token, force: true);
    } catch (e) {
      debugPrint('[Push] FCM 토큰 재등록 실패: $e');
      await _storage.setPendingFcmRegister(true);
    }
  }

  /// 권한이 새로 허용되었거나 pending 플래그가 있을 때 호출
  /// (앱 lifecycle resumed 훅에서 사용)
  Future<void> retryIfPending() async {
    final pending = await _storage.getPendingFcmRegister();
    if (!pending) return;
    debugPrint('[Push] pending 플래그 감지 — FCM 토큰 재등록 시도');
    await reregisterToken();
  }

  /// 서버에서 토큰 해제 (로그아웃 시)
  Future<void> unregisterToken() async {
    try {
      final token = await _storage.getFcmToken();
      // 빈 문자열도 스킵 — 이전 unregister 후 saveFcmToken('')로 비워진 상태일 수 있음
      if (token == null || token.isEmpty) {
        debugPrint('[Push] FCM 토큰 없음 — 해제 API 호출 스킵');
      } else {
        // 인증 토큰이 있을 때만 서버 호출 (로그아웃 시점엔 access token이 곧 클리어됨)
        final accessToken = await _storage.getAccessToken();
        if (accessToken == null || accessToken.isEmpty) {
          debugPrint('[Push] 인증 토큰 없음 — FCM 해제 API 호출 스킵');
        } else {
          await ApiClient.instance.delete(
            '/devices/push-token',
            body: {'token': token},
          );
          debugPrint('[Push] FCM 토큰 해제 완료');
        }
      }
    } catch (e) {
      debugPrint('[Push] FCM 토큰 해제 실패: $e');
    }
    // 로컬 토큰 삭제 → 다음 로그인 시 재등록되도록
    await _storage.saveFcmToken('');
    await _storage.setPendingFcmRegister(false);
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

}
