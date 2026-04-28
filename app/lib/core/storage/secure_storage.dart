import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 민감한 데이터(토큰) 안전 저장소
/// flutter_secure_storage 기반 — iOS Keychain / Android Keystore
class SecureStorage {
  SecureStorage._();

  static final SecureStorage _instance = SecureStorage._();
  static SecureStorage get instance => _instance;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // ─── 키 상수 ───
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';
  static const String _fcmTokenKey = 'fcm_token';
  static const String _fcmTokenRegisteredAtKey = 'fcm_token_registered_at';
  static const String _pendingFcmRegisterKey = 'pending_fcm_register';

  // ─── 액세스 토큰 ───
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  // ─── 리프레시 토큰 ───
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  // ─── 사용자 ID ───
  Future<void> saveUserId(String userId) async {
    await _storage.write(key: _userIdKey, value: userId);
  }

  Future<String?> getUserId() async {
    return _storage.read(key: _userIdKey);
  }

  // ─── FCM 토큰 ───
  Future<void> saveFcmToken(String token) async {
    await _storage.write(key: _fcmTokenKey, value: token);
  }

  Future<String?> getFcmToken() async {
    return _storage.read(key: _fcmTokenKey);
  }

  /// FCM 토큰이 서버에 마지막으로 등록된 시각 (TTL 판단용)
  Future<DateTime?> getFcmTokenRegisteredAt() async {
    final raw = await _storage.read(key: _fcmTokenRegisteredAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setFcmTokenRegisteredAt(DateTime at) async {
    await _storage.write(
      key: _fcmTokenRegisteredAtKey,
      value: at.toIso8601String(),
    );
  }

  /// 서버 등록 실패 후 재시도 대기 플래그
  Future<bool> getPendingFcmRegister() async {
    final raw = await _storage.read(key: _pendingFcmRegisterKey);
    return raw == 'true';
  }

  Future<void> setPendingFcmRegister(bool pending) async {
    if (pending) {
      await _storage.write(key: _pendingFcmRegisterKey, value: 'true');
    } else {
      await _storage.delete(key: _pendingFcmRegisterKey);
    }
  }

  // ─── 토큰 일괄 저장 ───
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
      saveUserId(userId),
    ]);
  }

  // ─── 전체 삭제 (로그아웃) ───
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userIdKey),
    ]);
  }

  // ─── 로그인 여부 확인 ───
  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
