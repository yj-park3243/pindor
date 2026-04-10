import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

class AuthRepository {
  final ApiClient _api;

  const AuthRepository(this._api);

  Future<Map<String, dynamic>> loginWithKakao(String accessToken) async {
    final response = await _api.post(
      '/auth/kakao',
      body: {'accessToken': accessToken},
    );
    return response['data'] as Map<String, dynamic>;
  }

  /// Apple 로그인
  /// NOTE: 서버에 POST /auth/apple 라우트가 아직 없음 — 서버 추가 필요
  Future<Map<String, dynamic>> loginWithApple({
    required String identityToken,
    required String authorizationCode,
  }) async {
    final response = await _api.post(
      '/auth/apple',
      body: {
        'identityToken': identityToken,
        'authorizationCode': authorizationCode,
      },
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _api.post(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _api.post('/auth/logout', body: {});
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ApiClient.instance);
});
