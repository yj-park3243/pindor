/// 앱 전역 상수
class AppConstants {
  AppConstants._();

  // ─── 타이머/TTL ───
  static const Duration chatRoomCacheTtl = Duration(minutes: 10);
  static const Duration matchPollInterval = Duration(seconds: 10);
  static const Duration matchPollMaxInterval = Duration(seconds: 60);
  static const Duration matchAcceptTimeout = Duration(minutes: 10);
  static const Duration toastDuration = Duration(seconds: 3);
  static const Duration syncRetryDelay = Duration(seconds: 30);

  // ─── 사이즈 ───
  static const double defaultAvatarSize = 48.0;
  static const double largeAvatarSize = 64.0;
  static const double smallAvatarSize = 36.0;
  static const double bottomNavHeight = 100.0;

  // ─── 페이지네이션 ───
  static const int defaultPageSize = 20;
  static const int chatPageSize = 50;
  static const int maxPageSize = 100;

  // ─── 채팅 ───
  static const int minChatCountForResult = 3;
  static const int maxGameProofPhotos = 2;
  static const int verificationCodeLength = 4;

  // ─── 폴링 ───
  static const int maxPollFailureCount = 5;
  static const int initialPollIntervalSeconds = 10;
}

/// 앱 전역 색상 (theme.dart의 AppTheme 외 반복되는 색상)
class AppColors {
  AppColors._();

  static const int backgroundDark = 0xFF0A0A0A;
  static const int cardDark = 0xFF1E1E1E;
  static const int cardBorder = 0xFF2A2A2A;
  static const int textMuted = 0xFF9CA3AF;
  static const int textDimmed = 0xFF6B7280;
  static const int dragHandle = 0xFF2A2A2A;
}
