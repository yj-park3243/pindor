import 'package:flutter/material.dart';

/// Material 3 기반 커스텀 테마
/// 티어 색상: 브론즈 #CD7F32 / 실버 #C0C0C0 / 골드 #FFD700 / 플래티넘 #E5E4E2
class AppTheme {
  AppTheme._();

  // ─── 브랜드 색상 ───
  static const Color primaryColor = Color(0xFFEA733A);   // 오렌지
  static const Color primaryDark = Color(0xFFD4612A);
  static const Color primaryLight = Color(0xFFFF8F5A);

  static const Color secondaryColor = Color(0xFF22C55E); // 그린 (성공)
  static const Color acceptColor = Color(0xFF2563EB);    // 블루 (수락)
  static const Color rejectColor = Color(0xFFEF4444);    // 레드 (거절/삭제)
  static const Color errorColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF59E0B);

  // ─── 배경/표면 색상 (다크 테마 기본값) ───
  static const Color backgroundLight = Color(0xFF0A0A0A); // 거의 블랙
  static const Color surfaceLight = Color(0xFF1A1A1A);
  static const Color cardLight = Color(0xFF1E1E1E);

  static const Color backgroundDark = Color(0xFF0A0A0A);
  static const Color surfaceDark = Color(0xFF1A1A1A);
  static const Color cardDark = Color(0xFF1E1E1E);

  // ─── 텍스트 색상 ───
  static const Color textPrimary = Color(0xFFFFFFFF);     // 화이트
  static const Color textSecondary = Color(0xFF9CA3AF);   // 라이트 그레이
  static const Color textDisabled = Color(0xFF4B5563);    // 다크 그레이
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ─── 티어 색상 (7단계) ───
  static const Color grandmasterColor = Color(0xFFFF4500); // 레드 오렌지
  static const Color masterColor = Color(0xFF9B59B6);      // 퍼플
  static const Color platinumColor = Color(0xFFE5E4E2);    // 플래티넘
  static const Color goldColor = Color(0xFFFFD700);        // 골드
  static const Color silverColor = Color(0xFFC0C0C0);      // 실버
  static const Color bronzeColor = Color(0xFFCD7F32);      // 브론즈
  static const Color ironColor = Color(0xFF71797E);        // 아이언 (다크그레이)

  static Color tierColor(String tier) {
    switch (tier.toUpperCase()) {
      case 'GRANDMASTER':
        return grandmasterColor;
      case 'MASTER':
        return masterColor;
      case 'PLATINUM':
        return platinumColor;
      case 'GOLD':
        return goldColor;
      case 'SILVER':
        return silverColor;
      case 'BRONZE':
        return bronzeColor;
      case 'IRON':
        return ironColor;
      default:
        return ironColor;
    }
  }

  // ─── 라이트 테마 (실제로는 다크 스타일) ───
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      error: errorColor,
      surface: surfaceLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundLight,
      // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화

      // AppBar 테마
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: surfaceLight,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // 카드 테마
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // 버튼 테마
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(
            // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // 입력 필드 테마
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333333), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(
          color: textDisabled,
          fontSize: 14,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
      ),

      // BottomNavigationBar 테마 (레거시)
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF111111),
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      ),

      // NavigationBar 테마 (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor, size: 24);
          }
          return const IconThemeData(color: textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: textSecondary,
          );
        }),
      ),

      // 텍스트 테마
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
        ),
      ),

      // Chip 테마
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2A2A2A),
        selectedColor: primaryColor.withOpacity(0.25),
        labelStyle: const TextStyle(
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // Divider 테마
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A2A),
        thickness: 1,
        space: 1,
      ),

      // SnackBar 테마
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        contentTextStyle: const TextStyle(
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
          fontSize: 14,
          color: Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ─── 다크 테마 ───
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: primaryColor,
      secondary: secondaryColor,
      error: errorColor,
      surface: surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
      scaffoldBackgroundColor: backgroundDark,

      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: surfaceDark,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          // fontFamily: 'Pretendard', // 추후 폰트 에셋 추가 시 활성화
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF111111),
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF9CA3AF),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),

      // NavigationBar 테마 (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor, size: 24);
          }
          return const IconThemeData(color: Color(0xFF9CA3AF), size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Color(0xFF9CA3AF),
          );
        }),
      ),
    );
  }
}
