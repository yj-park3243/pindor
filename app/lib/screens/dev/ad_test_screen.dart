import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../core/version/version_check_service.dart';
import '../../widgets/common/native_ad_card.dart';

/// 숨겨진 광고 테스트 페이지.
/// 마이페이지 → 설정 → "앱 버전"을 20번 탭하면 진입.
class AdTestScreen extends StatelessWidget {
  const AdTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('광고 테스트'),
        backgroundColor: AppTheme.backgroundLight,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'showAd (서버 토글): ${VersionCheckService.showAd}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'OFF면 카드 자체가 렌더링되지 않습니다. admin → 시스템 설정 → 광고에서 ON 후 앱 재실행.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const NativeAdCard(highlightAdLabel: true),
          ],
        ),
      ),
    );
  }
}
