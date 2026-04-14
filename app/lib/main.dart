import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'providers/font_scale_provider.dart';
import 'core/network/api_client.dart';
import 'core/error/error_reporter.dart';
import 'core/push/local_notification_service.dart';
import 'core/push/push_notification_service.dart';
import 'providers/auth_provider.dart';
import 'repositories/pin_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/matching_repository.dart';
import 'providers/active_match_provider.dart';
import 'core/offline/offline_queue_service.dart';
import 'core/version/version_check_service.dart';
import 'widgets/common/app_toast.dart';

/// FCM 백그라운드 메시지 핸들러 (최상위 함수여야 함)
/// 앱이 백그라운드 또는 종료 상태일 때 FCM 메시지 수신 처리
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 핸들러는 별도 isolate에서 실행되므로 Firebase 재초기화 필요
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await LocalNotificationService.instance.showFromRemoteMessage(message);
}

Future<void> main() async {
  // runZonedGuarded: Zone 내 비동기 에러 캐치
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 상태바 스타일 설정 (투명 배경, 어두운 아이콘)
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      // 화면 방향 고정 (세로)
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Firebase 초기화
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // API 클라이언트 초기화
      ApiClient.instance.initialize();

      // 에러 리포터 초기화 (API 클라이언트 이후)
      ErrorReporter.instance.initialize();

      // Flutter 프레임워크 에러 핸들러 등록
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        // 기존 핸들러 유지 (디버그 콘솔 출력 등)
        originalOnError?.call(details);
        ErrorReporter.instance.reportError(
          details.exception,
          details.stack,
          screenName: details.context?.toDescription(),
        );
      };

      // 플랫폼 디스패처 비동기 에러 핸들러 등록
      PlatformDispatcher.instance.onError = (error, stack) {
        ErrorReporter.instance.reportError(error, stack);
        return true; // true 반환 시 기본 에러 처리 스킵
      };

      // 네이버 지도 SDK 초기화
      await FlutterNaverMap().init(
        clientId: '539desbv96',
        onAuthFailed: (ex) => debugPrint('NaverMap auth failed: $ex'),
      );

      // FCM 백그라운드 핸들러 등록
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 로컬 알림 서비스 초기화 (Android 채널 생성)
      await LocalNotificationService.instance.initialize();

      // timeago 한국어 로케일 설정
      timeago.setLocaleMessages('ko', timeago.KoMessages());

      // 이미지 메모리 캐시 한도 설정 (200MB, 최대 500장)
      PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 500;

      runApp(
        const ProviderScope(
          child: PindorApp(),
        ),
      );
    },
    // Zone 내 캐치되지 않은 에러 처리
    (error, stack) {
      ErrorReporter.instance.reportError(error, stack);
    },
  );
}

class PindorApp extends ConsumerWidget {
  const PindorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '핀돌',
      debugShowCheckedModeBanner: false,

      // 테마
      theme: AppTheme.lightTheme,

      // 라우터
      routerConfig: router,

      // 빌더: 푸시 알림 서비스 초기화 (앱 컨텍스트 확보 후)
      builder: (context, child) {
        final fontScale = ref.watch(fontScaleProvider);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: _AppInitializer(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// 앱 초기화 위젯
/// - 푸시 알림 서비스를 컨텍스트 확보 후 초기화
/// - 인앱 알림 오버레이 레이어 설정
class _AppInitializer extends ConsumerStatefulWidget {
  final Widget child;
  const _AppInitializer({required this.child});

  @override
  ConsumerState<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends ConsumerState<_AppInitializer>
    with WidgetsBindingObserver {
  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 다음 프레임에서 초기화 (BuildContext 확보 후)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePush();
      // 버전 체크 (인증 불필요, 실패해도 앱 계속 동작)
      VersionCheckService.check(context);
      // 오프라인 큐 감시 시작 + 대기 작업 처리
      ref.read(offlineQueueServiceProvider).processQueue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStaleData();
    }
  }

  /// 앱 포그라운드 복귀 시 TTL 만료 데이터만 선택적 갱신
  Future<void> _refreshStaleData() async {
    final isAuth = ref.read(isAuthenticatedProvider);
    if (!isAuth) return;

    final userId = ref.read(currentUserProvider)?.id;

    // 병렬로 TTL 체크 + 갱신
    await Future.wait([
      ref.read(pinRepositoryProvider).refreshIfStale(),
      ref.read(chatRepositoryProvider).refreshRoomsIfStale(),
      ref.read(matchingRepositoryProvider).refreshIfStale(),
      if (userId != null)
        ref.read(userRepositoryProvider).refreshMeIfStale(userId),
    ]);
  }

  Future<void> _initializePush() async {
    if (_pushInitialized) return;
    _pushInitialized = true;

    await PushNotificationService.instance.initialize();

    // 딥링크 콜백 연결
    PushNotificationService.instance.onDeepLink = (deepLink) {
      if (mounted) {
        ref.read(routerProvider).push(deepLink);
      }
    };

    // 로컬 알림 탭 콜백
    LocalNotificationService.instance.onNotificationTap = (payload) {
      if (payload != null && mounted) {
        ref.read(routerProvider).push(payload);
      }
    };

    // 푸시 초기화 완료 후 활성 매칭 체크 → 화면 잠금
    unawaited(_checkActiveMatchAndRedirect());
  }

  /// 앱 시작 시 활성 매칭이 있으면 해당 화면으로 강제 이동
  Future<void> _checkActiveMatchAndRedirect() async {
    final isAuth = ref.read(isAuthenticatedProvider);
    if (!isAuth) return;

    try {
      final activeMatch = await ref.read(activeMatchProvider.future);
      if (activeMatch != null && mounted) {
        if (activeMatch.status == 'PENDING_ACCEPT') {
          ref.read(routerProvider).go('/matches/${activeMatch.id}/accept');
        } else if (activeMatch.status == 'CHAT' || activeMatch.status == 'CONFIRMED') {
          ref.read(routerProvider).go('/matches/${activeMatch.id}');
        }
      }
    } catch (e) {
      // 활성 매칭 조회 실패는 무시 (앱 동작 계속)
      debugPrint('[AppInitializer] 활성 매칭 체크 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
