/// 앱 환경 설정
/// API URL, 소켓 URL, 환경 변수 관리
class AppConfig {
  AppConfig._();

  // ─── 환경 분기 ───
  static const String _env =
      String.fromEnvironment('ENVIRONMENT', defaultValue: 'production');

  static bool get isDevelopment => _env == 'development';
  static bool get isProduction => _env == 'production';

  // ─── API 설정 ───
  static const String _apiHost = 'https://api.pins.kr';

  static String get apiBaseUrl => '$_apiHost/v1';
  static String get socketUrl => _apiHost;

  // ─── 카카오 설정 ───
  static const String kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '',
  );

  // ─── 타임아웃 설정 ───
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // ─── 페이지네이션 기본값 ───
  static const int defaultPageSize = 20;
  static const int chatPageSize = 50;

  // ─── 매칭 설정 ───
  static const int defaultMatchRadiusKm = 10;
  static const int minMatchRadiusKm = 1;
  static const int maxMatchRadiusKm = 50;

  // ─── 이미지 업로드 제한 ───
  static const int maxProfileImageSizeMb = 5;
  static const int maxGameImageSizeMb = 10;
  static const int maxPostImageCount = 5;
  static const int maxGameProofImageCount = 3;

  // ─── 점수/티어 기준 (폴백용 — 유저 수 30명 미만 시 서버에서 사용) ───
  static const int ironMin = 100;
  static const int bronzeMin = 900;
  static const int silverMin = 1100;
  static const int goldMin = 1300;
  static const int platinumMin = 1500;
  static const int masterMin = 1650;
  static const int grandmasterMin = 1800;

  // ─── 소켓 재연결 설정 ───
  static const int socketReconnectDelay = 1000; // ms
  static const int socketMaxReconnectAttempts = 10;

  // ─── 앱 버전 ───
  static const String appVersion = '1.0.0';
  static const int appBuild = 4;
}
