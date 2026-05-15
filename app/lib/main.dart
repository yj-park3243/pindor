import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'widgets/common/ambient_glow_background.dart';
import 'providers/font_scale_provider.dart';
import 'core/network/api_client.dart';
import 'providers/matching_provider.dart';
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
      // E2E 테스트(TEST_MODE)에선 스킵 — NaverMap iOS SDK 가 위치 권한 다이얼로그를
      // 띄워 시뮬레이터 화면을 가리고 테스트를 막는다. 테스트 경로엔 지도가 없다.
      const isE2E = bool.fromEnvironment('TEST_MODE', defaultValue: false);
      if (!isE2E) {
        await FlutterNaverMap().init(
          clientId: '539desbv96',
          onAuthFailed: (ex) => debugPrint('NaverMap auth failed: $ex'),
        );
      }

      // Google Mobile Ads 초기화 (실패해도 앱은 계속 동작)
      unawaited(MobileAds.instance.initialize());

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

      // 한국어 로케일
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // 테마
      theme: AppTheme.lightTheme,

      // 라우터
      routerConfig: router,

      // 빌더: 푸시 알림 서비스 초기화 (앱 컨텍스트 확보 후)
      builder: (context, child) {
        final fontScale = ref.watch(fontScaleProvider);
        final location = router
            .routeInformationProvider
            .value
            .uri
            .path;
        final seed = location.codeUnits.fold<int>(0, (a, b) => a + b);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: AmbientGlowBackground(
            seed: seed,
            child: _AppInitializer(child: child ?? const SizedBox.shrink()),
          ),
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
    // 401 토큰 갱신 실패 시 강제 로그아웃
    ApiClient.instance.onForceLogout = () {
      debugPrint('[Auth] 토큰 만료 — 로그인 화면으로 이동');
      ref.read(authStateProvider.notifier).logout();
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePush();
      // 버전 체크 (인증 불필요, 실패해도 앱 계속 동작)
      debugPrint('[VersionCheck] _AppInitializer PostFrame — check 시작');
      VersionCheckService.check(context);
      // 오프라인 큐 감시 시작 + 대기 작업 처리
      ref.read(offlineQueueServiceProvider).processQueue();
    });

    // 라우터 변경/위젯 rebuild 시 누락 가능성 대비 — 5초 후 한 번 더 보강 체크
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      debugPrint('[VersionCheck] 5초 보강 — check 재시도');
      VersionCheckService.check(context);
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
      // 활성 매칭 여부에 따라 소켓 연결/해제
      syncSocketConnection(ref);
      // 권한 변경/이전 등록 실패 등으로 누락된 FCM 토큰 재시도
      _retryFcmIfNeeded();
    }
  }

  /// 앱 resume 시 FCM 토큰 재시도
  /// - pending 플래그가 있으면 무조건 재시도 (이전 등록 실패 케이스)
  /// - 인증된 상태면 항상 한 번 호출 — TTL/캐시 검사로 내부 스킵 처리됨
  Future<void> _retryFcmIfNeeded() async {
    final isAuth = ref.read(isAuthenticatedProvider);
    if (!isAuth) return;
    await PushNotificationService.instance.retryIfPending();
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
        final router = ref.read(routerProvider);
        // ShellRoute 내부 경로면 go, 바깥이면 홈 먼저 확보 후 push
        if (deepLink.startsWith('/home') || deepLink.startsWith('/matches') ||
            deepLink.startsWith('/map') || deepLink.startsWith('/profile')) {
          router.go(deepLink);
        } else {
          router.go('/home');
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) router.push(deepLink);
          });
        }
      }
    };

    // 로컬 알림 탭 콜백
    LocalNotificationService.instance.onNotificationTap = (payload) {
      if (payload != null && mounted) {
        final router = ref.read(routerProvider);
        if (payload.startsWith('/home') || payload.startsWith('/matches') ||
            payload.startsWith('/map') || payload.startsWith('/profile')) {
          router.go(payload);
        } else {
          router.go('/home');
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) router.push(payload);
          });
        }
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
