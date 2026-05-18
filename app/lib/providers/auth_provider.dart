import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../core/network/api_client.dart';
import '../core/network/socket_service.dart';
import '../core/storage/secure_storage.dart';
import '../core/push/push_notification_service.dart';
import '../data/local/database_provider.dart';
import '../models/user.dart';
import '../repositories/user_repository.dart';

/// 인증 상태
class AuthState {
  final bool isAuthenticated;
  final User? user;
  final bool isNewUser;
  final bool isVerified;

  const AuthState({
    required this.isAuthenticated,
    this.user,
    this.isNewUser = false,
    this.isVerified = false, // 안전 기본값 — 명시 안 한 경로에서 본인인증 강제 흐름 유지
  });

  static const unauthenticated = AuthState(isAuthenticated: false);

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isNewUser,
    bool? isVerified,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isNewUser: isNewUser ?? this.isNewUser,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}

/// 인증 상태 Notifier
class AuthNotifier extends AsyncNotifier<AuthState> {
  final _storage = SecureStorage.instance;
  final _api = ApiClient.instance;
  final _socket = SocketService.instance;

  @override
  Future<AuthState> build() async {
    // 앱 시작 시 저장된 토큰으로 자동 로그인 시도
    return await _checkAutoLogin();
  }

  Future<AuthState> _checkAutoLogin() async {
    try {
      final hasToken = await _storage.hasValidToken();
      debugPrint('[AuthAutoLogin] hasToken=$hasToken');
      if (!hasToken) return AuthState.unauthenticated;

      // FCM 토큰 재등록 (인증 토큰 확보된 상태)
      unawaited(PushNotificationService.instance.reregisterToken());
      // 소켓은 매칭 데이터 로드 후 필요 시에만 연결 (syncSocketConnection)

      // 서버에서 내 정보 조회 → 로컬 DB에도 저장
      final repo = ref.read(userRepositoryProvider);
      final user = await repo.getMe();

      // 가입 단계 판단: 본인인증 미완료 or 프로필 미설정 → isNewUser 유지
      final isVerified = user?.isVerified ?? false;
      final hasNickname = user?.nickname != null && user!.nickname!.isNotEmpty;
      final isSetupIncomplete = !isVerified || !hasNickname;

      return AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isSetupIncomplete,
        isVerified: isVerified,
      );
    } on ApiException catch (e) {
      // 401/403 = 토큰 만료 → 로그아웃
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _storage.clearTokens();
        return AuthState.unauthenticated;
      }
      // 그 외 에러 (네트워크 등) = 토큰 유지, 인증 상태 유지.
      // 단 isVerified는 false로 — user info 못 받았으면 본인인증 화면으로 강제해
      // 인증 도중 종료 → 재시작 시 이어지도록 한다.
      return AuthState(isAuthenticated: true, isVerified: false);
    } catch (e) {
      // 네트워크 에러 등 — 토큰이 있으면 인증 유지 (isVerified=false)
      final hasToken = await _storage.hasValidToken();
      if (hasToken) {
        return AuthState(isAuthenticated: true, isVerified: false);
      }
      return AuthState.unauthenticated;
    }
  }

  /// Firebase 이메일 회원가입
  Future<void> signupWithFirebase({
    required String email,
    required String password,
  }) async {
    final previousState = state;
    state = const AsyncLoading();
    try {
      debugPrint('[AuthProvider] Firebase createUserWithEmailAndPassword 호출');
      final credential = await fb.FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      debugPrint('[AuthProvider] Firebase 계정 생성 완료: uid=${credential.user?.uid}');

      final idToken = await credential.user?.getIdToken();
      if (idToken == null) throw Exception('Firebase ID 토큰을 가져올 수 없습니다.');
      debugPrint('[AuthProvider] idToken 획득. 서버 호출 시작');

      final response = await _api.post(
        '/auth/firebase/signup',
        body: {'idToken': idToken, 'agreedTerms': true},
      );
      debugPrint('[AuthProvider] 서버 응답 OK');

      await _handleAuthResponse(response, isNewUser: true);
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('[AuthProvider] FirebaseAuthException: code=${e.code} msg=${e.message}');
      state = previousState;
      rethrow;
    } catch (e, st) {
      debugPrint('[AuthProvider] signup 실패: $e');
      debugPrint('[AuthProvider] stack: $st');
      state = previousState;
      rethrow;
    }
  }

  /// Firebase 이메일 로그인
  Future<void> loginWithFirebase({
    required String email,
    required String password,
  }) async {
    final previousState = state;
    state = const AsyncLoading();
    try {
      // 1. Firebase Auth로 로그인
      final credential = await fb.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final idToken = await credential.user?.getIdToken();
      if (idToken == null) throw Exception('Firebase ID 토큰을 가져올 수 없습니다.');

      // 2. 서버에 전달
      final response = await _api.post(
        '/auth/firebase/login',
        body: {'idToken': idToken},
      );

      await _handleAuthResponse(response, isNewUser: false);
    } on fb.FirebaseAuthException catch (e) {
      state = previousState;
      rethrow;
    } catch (e) {
      state = previousState;
      rethrow;
    }
  }

  /// 공통 인증 응답 처리 (Firebase 이메일 가입/로그인 공통)
  Future<void> _handleAuthResponse(
    Map<String, dynamic> response, {
    required bool isNewUser,
  }) async {
    final data = response['data'] as Map<String, dynamic>;
    final accessToken = data['accessToken'] as String;
    final refreshToken = data['refreshToken'] as String;
    final userData = data['user'] as Map<String, dynamic>;
    final actualIsNewUser = userData['isNewUser'] as bool? ?? isNewUser;
    final isVerified = userData['isVerified'] as bool? ?? false;

    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userData['id'] as String,
    );

    _socket.connect(accessToken);
    unawaited(PushNotificationService.instance.reregisterToken());

    User user;
    if (!actualIsNewUser) {
      final repo = ref.read(userRepositoryProvider);
      user = (await repo.getMe()) ??
          User(
            id: userData['id'] as String,
            nickname: userData['nickname'] as String? ?? '',
            status: 'ACTIVE',
            createdAt: DateTime.now(),
            isVerified: isVerified,
          );
    } else {
      user = User(
        id: userData['id'] as String,
        nickname: userData['nickname'] as String? ?? '',
        status: 'ACTIVE',
        createdAt: DateTime.now(),
        isVerified: isVerified,
      );
    }

    debugPrint('[AuthProvider] state 갱신: isAuthenticated=true, isNewUser=$actualIsNewUser, isVerified=$isVerified');
    state = AsyncData(AuthState(
      isAuthenticated: true,
      user: user,
      isNewUser: actualIsNewUser,
      isVerified: isVerified,
    ));
  }

  /// 카카오 로그인
  Future<void> loginWithKakao(String kakaoAccessToken) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await _api.post(
        '/auth/kakao',
        body: {'accessToken': kakaoAccessToken},
      );

      final data = response['data'] as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String;
      final userData = data['user'] as Map<String, dynamic>;
      final isNewUser = userData['isNewUser'] as bool? ?? false;
      final isVerified = userData['isVerified'] as bool? ?? false;

      // 토큰 저장
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userData['id'] as String,
      );

      // 소켓 연결
      _socket.connect(accessToken);

      // FCM 토큰 재등록 (로그인 직후 인증 토큰 확보 시점)
      unawaited(PushNotificationService.instance.reregisterToken());

      // 사용자 정보 불러오기 → 로컬 DB에도 저장
      User user;
      if (!isNewUser) {
        final repo = ref.read(userRepositoryProvider);
        user = (await repo.getMe())!;
      } else {
        user = User(
          id: userData['id'] as String,
          nickname: userData['nickname'] as String? ?? '',
          status: 'ACTIVE',
          createdAt: DateTime.now(),
          isVerified: isVerified,
        );
      }

      return AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
        isVerified: isVerified,
      );
    });
  }

  /// Google 로그인
  Future<void> loginWithGoogle() async {
    final previousState = state;
    state = const AsyncLoading();
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) throw Exception('Google 로그인 취소됨');

      final GoogleSignInAuthentication auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) throw Exception('Google ID Token을 받지 못했습니다');

      final response = await _api.post(
        '/auth/google',
        body: {'idToken': idToken},
      );

      final data = response['data'] as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String;
      final userData = data['user'] as Map<String, dynamic>;
      final isNewUser = userData['isNewUser'] as bool? ?? false;
      final isVerified = userData['isVerified'] as bool? ?? false;

      // 토큰 저장
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userData['id'] as String,
      );

      // 소켓 연결
      _socket.connect(accessToken);

      // FCM 토큰 재등록 (로그인 직후 인증 토큰 확보 시점)
      unawaited(PushNotificationService.instance.reregisterToken());

      // 사용자 정보 불러오기 → 로컬 DB에도 저장
      User user;
      if (!isNewUser) {
        final repo = ref.read(userRepositoryProvider);
        user = (await repo.getMe())!;
      } else {
        user = User(
          id: userData['id'] as String,
          nickname: userData['nickname'] as String? ?? '',
          status: 'ACTIVE',
          createdAt: DateTime.now(),
          isVerified: isVerified,
        );
      }

      state = AsyncData(AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
        isVerified: isVerified,
      ));
    } catch (e, st) {
      state = previousState;
      rethrow;
    }
  }

  /// Apple 로그인 — 라우팅 타이밍 이슈를 피하려고 결과를 직접 반환
  Future<({bool isNewUser, bool isVerified})> loginWithApple() async {
    final previousState = state;
    state = const AsyncLoading();
    try {
      print('[Apple] credential 요청 시작');
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      print('[Apple] credential 수신: userId=${credential.userIdentifier}, email=${credential.email}, givenName=${credential.givenName}, familyName=${credential.familyName}');

      final identityToken = credential.identityToken;
      final authorizationCode = credential.authorizationCode;
      if (identityToken == null) throw Exception('Apple Identity Token을 받지 못했습니다');

      final fullName = [
        credential.givenName,
        credential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

      print('[Apple] 서버에 /auth/apple 요청 (email=${credential.email != null}, fullName=${fullName.isNotEmpty})');
      final response = await _api.post(
        '/auth/apple',
        body: {
          'identityToken': identityToken,
          'authorizationCode': authorizationCode,
          if (credential.email != null) 'email': credential.email,
          if (fullName.isNotEmpty) 'fullName': fullName,
        },
      );

      final data = response['data'] as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String;
      final userData = data['user'] as Map<String, dynamic>;
      final isNewUser = userData['isNewUser'] as bool? ?? false;
      final isVerified = userData['isVerified'] as bool? ?? false;
      print('[Apple] 서버 응답 OK: userId=${userData['id']}, isNewUser=$isNewUser, isVerified=$isVerified');

      // 토큰 저장
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userData['id'] as String,
      );

      // 소켓 연결
      _socket.connect(accessToken);

      // FCM 토큰 재등록 (로그인 직후 인증 토큰 확보 시점)
      unawaited(PushNotificationService.instance.reregisterToken());

      // 사용자 정보 불러오기 → 로컬 DB에도 저장
      User user;
      if (!isNewUser) {
        final repo = ref.read(userRepositoryProvider);
        user = (await repo.getMe())!;
      } else {
        user = User(
          id: userData['id'] as String,
          nickname: userData['nickname'] as String? ?? '',
          status: 'ACTIVE',
          createdAt: DateTime.now(),
          isVerified: isVerified,
        );
      }

      state = AsyncData(AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
        isVerified: isVerified,
      ));
      print('[Apple] 로그인 완료 → 라우팅 결정 (isNewUser=$isNewUser, isVerified=$isVerified)');
      return (isNewUser: isNewUser, isVerified: isVerified);
    } on SignInWithAppleAuthorizationException catch (e) {
      print('[Apple] 사용자 취소 또는 인증 실패: code=${e.code}, message=${e.message}');
      state = previousState;
      rethrow;
    } catch (e, st) {
      print('[Apple] 로그인 실패: $e');
      print('[Apple] stack: $st');
      state = previousState;
      rethrow;
    }
  }

  /// 사용자 정보 갱신 — user뿐만 아니라 isNewUser/isVerified도 재계산
  Future<void> refreshUser() async {
    if (state.valueOrNull?.isAuthenticated != true) return;

    try {
      final repo = ref.read(userRepositoryProvider);
      final user = await repo.getMe();
      if (user != null) {
        final isVerified = user.isVerified ?? false;
        final hasNickname =
            user.nickname != null && user.nickname!.isNotEmpty;
        final isSetupIncomplete = !isVerified || !hasNickname;
        state = AsyncData(state.requireValue.copyWith(
          user: user,
          isNewUser: isSetupIncomplete,
          isVerified: isVerified,
        ));
      }
    } catch (e) {
      // 갱신 실패 시 현재 상태 유지
    }
  }

  /// 회원가입 모든 단계 완료 — isNewUser=false로 강제
  void completeSetup() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(isNewUser: false));
  }

  /// 로그아웃 재진입 방지 플래그 — onForceLogout이 logout 중에 다시 호출되어
  /// 무한 루프를 만드는 케이스 차단
  bool _isLoggingOut = false;

  /// 로그아웃
  Future<void> logout() async {
    if (_isLoggingOut) return;
    if (state.valueOrNull?.isAuthenticated == false) {
      // 이미 unauthenticated — 어차피 호출할 필요 없음
      return;
    }
    _isLoggingOut = true;
    try {
      // /auth/logout: 토큰이 살아 있을 때만 호출 (없으면 401 → 또 logout 트리거)
      final accessToken = await _storage.getAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        try {
          await _api.post('/auth/logout');
        } catch (_) {}
      }

      try {
        await PushNotificationService.instance.unregisterToken();
      } catch (_) {}

      PushNotificationService.instance.onDeepLink = null;
      _socket.disconnect();
      await _storage.clearTokens();

      // 로컬 DB 전체 정리
      await ref.read(appDatabaseProvider).clearAll();

      // SharedPreferences 정리 (종목/핀 설정 등)
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      state = const AsyncData(AuthState.unauthenticated);
    } finally {
      _isLoggingOut = false;
    }
  }

  /// 회원 탈퇴
  Future<void> deleteAccount({String? reason}) async {
    final userRepo = ref.read(userRepositoryProvider);
    // API 실패 시 토큰 삭제/로그아웃 하지 않고 에러를 rethrow
    await userRepo.deleteAccount(reason: reason);

    // API 성공한 경우에만 cleanup 진행
    try {
      await PushNotificationService.instance.unregisterToken();
    } catch (_) {}

    PushNotificationService.instance.onDeepLink = null;
    _socket.disconnect();
    await _storage.clearTokens();
    await ref.read(appDatabaseProvider).clearAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    state = const AsyncData(AuthState.unauthenticated);
  }

  /// 사용자 정보 직접 업데이트 (프로필 수정 후)
  void updateUser(User user) {
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(user: user));
    }
  }

  /// KCP 본인인증 완료 후 상태 업데이트
  void completeVerification({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> userData,
    required bool isNewUser,
  }) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userData['id'] as String,
    );

    final updatedUser = currentState.user?.copyWith(isVerified: true) ??
        User(
          id: userData['id'] as String,
          nickname: userData['nickname'] as String? ?? '',
          status: 'ACTIVE',
          createdAt: DateTime.now(),
          isVerified: true,
        );

    state = AsyncData(AuthState(
      isAuthenticated: true,
      user: updatedUser,
      isNewUser: isNewUser,
      isVerified: true,
    ));
  }
}

/// 인증 상태 프로바이더
final authStateProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// 현재 사용자 편의 프로바이더
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.user;
});

/// 인증 여부 편의 프로바이더
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.isAuthenticated ?? false;
});
