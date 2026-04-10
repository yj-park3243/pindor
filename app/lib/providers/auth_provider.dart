import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  const AuthState({
    required this.isAuthenticated,
    this.user,
    this.isNewUser = false,
  });

  static const unauthenticated = AuthState(isAuthenticated: false);

  AuthState copyWith({bool? isAuthenticated, User? user, bool? isNewUser}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isNewUser: isNewUser ?? this.isNewUser,
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
      if (!hasToken) return AuthState.unauthenticated;

      // 소켓 연결 (토큰이 있으면 우선 연결)
      final accessToken = await _storage.getAccessToken();
      if (accessToken != null) {
        _socket.connect(accessToken);
      }

      // 서버에서 내 정보 조회 → 로컬 DB에도 저장
      final repo = ref.read(userRepositoryProvider);
      final user = await repo.getMe();

      return AuthState(isAuthenticated: true, user: user);
    } on ApiException catch (e) {
      // 401/403 = 토큰 만료 → 로그아웃
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _storage.clearTokens();
        return AuthState.unauthenticated;
      }
      // 그 외 에러 (네트워크 등) = 토큰 유지, 인증 상태 유지
      return AuthState(isAuthenticated: true);
    } catch (e) {
      // 네트워크 에러 등 — 토큰이 있으면 인증 유지
      final hasToken = await _storage.hasValidToken();
      if (hasToken) {
        return AuthState(isAuthenticated: true);
      }
      return AuthState.unauthenticated;
    }
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

      // 토큰 저장
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userData['id'] as String,
      );

      // 소켓 연결
      _socket.connect(accessToken);

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
        );
      }

      return AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
      );
    });
  }

  /// Google 로그인
  Future<void> loginWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
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

      // 토큰 저장
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userData['id'] as String,
      );

      // 소켓 연결
      _socket.connect(accessToken);

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
        );
      }

      return AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
      );
    });
  }

  /// Apple 로그인
  Future<void> loginWithApple() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final identityToken = credential.identityToken;
      final authorizationCode = credential.authorizationCode;
      if (identityToken == null) throw Exception('Apple Identity Token을 받지 못했습니다');

      final fullName = [
        credential.givenName,
        credential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

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

      // 토큰 저장
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userData['id'] as String,
      );

      // 소켓 연결
      _socket.connect(accessToken);

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
        );
      }

      return AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
      );
    });
  }

  /// 사용자 정보 갱신
  Future<void> refreshUser() async {
    if (state.valueOrNull?.isAuthenticated != true) return;

    try {
      final repo = ref.read(userRepositoryProvider);
      final user = await repo.getMe();
      if (user != null) {
        state = AsyncData(state.requireValue.copyWith(user: user));
      }
    } catch (e) {
      // 갱신 실패 시 현재 상태 유지
    }
  }

  /// 로그아웃
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}

    try {
      await PushNotificationService.instance.unregisterToken();
    } catch (_) {}

    PushNotificationService.instance.onDeepLink = null;
    _socket.disconnect();
    await _storage.clearTokens();

    // 로컬 DB 전체 정리
    await ref.read(appDatabaseProvider).clearAll();

    state = const AsyncData(AuthState.unauthenticated);
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

    state = const AsyncData(AuthState.unauthenticated);
  }

  /// 사용자 정보 직접 업데이트 (프로필 수정 후)
  void updateUser(User user) {
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(user: user));
    }
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
