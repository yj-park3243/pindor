import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/font_scale_provider.dart';

/// 글자 크기 설정 화면 (신규 가입 플로우 2/4)
class FontSizeSetupScreen extends ConsumerStatefulWidget {
  const FontSizeSetupScreen({super.key});

  @override
  ConsumerState<FontSizeSetupScreen> createState() =>
      _FontSizeSetupScreenState();
}

class _FontSizeSetupScreenState extends ConsumerState<FontSizeSetupScreen> {
  @override
  Widget build(BuildContext context) {
    final currentScale = ref.watch(fontScaleProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('글자 크기 설정'),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 진행 표시 바 (2/4)
              const _StepProgressBar(currentStep: 2, totalSteps: 4),
              const SizedBox(height: 6),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('2/4',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 20),

              const Text(
                '편한 글자 크기를\n선택해주세요',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '설정에서 언제든 변경할 수 있습니다.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 28),

              // 미리보기 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '미리보기',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDisabled,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '핀돌에서 대결 상대를 찾아보세요!',
                      style: TextStyle(
                        fontSize: 16 * currentScale,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '내 근처 스포츠 매칭 플랫폼',
                      style: TextStyle(
                        fontSize: 13 * currentScale,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 옵션 목록
              ...FontScaleNotifier.presets.map((preset) {
                final (label, value) = preset;
                final isSelected = (value - currentScale).abs() < 0.01;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(fontScaleProvider.notifier).setScale(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor.withOpacity(0.1)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : const Color(0xFF2A2A2A),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(value * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? AppTheme.primaryColor.withOpacity(0.7)
                                  : AppTheme.textDisabled,
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded,
                                color: AppTheme.primaryColor, size: 22),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const Spacer(),

              // 다음 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.sportProfileSetup),
                  child: const Text('다음', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상단 진행 표시 바
class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepProgressBar(
      {required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Row(
        children: List.generate(
          totalSteps,
          (index) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              height: 5,
              decoration: BoxDecoration(
                color: index < currentStep
                    ? AppTheme.primaryColor
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
