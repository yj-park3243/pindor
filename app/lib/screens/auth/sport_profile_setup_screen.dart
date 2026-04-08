import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../repositories/profile_repository.dart';

/// 스포츠 프로필 설정 화면
/// 종목 선택 (그리드), G핸디 입력, 초기 점수 표시
class SportProfileSetupScreen extends ConsumerStatefulWidget {
  const SportProfileSetupScreen({super.key});

  @override
  ConsumerState<SportProfileSetupScreen> createState() =>
      _SportProfileSetupScreenState();
}

class _SportProfileSetupScreenState
    extends ConsumerState<SportProfileSetupScreen> {
  String _selectedSport = 'GOLF';
  final _gHandiController = TextEditingController();
  final _displayNameController = TextEditingController();
  double _gHandicap = 20.0;
  bool _isLoading = false;

  // 종목 목록 (key, 이름, 아이콘)
  static const _sports = [
    ('GOLF', '골프', Icons.sports_golf),
    ('TABLE_TENNIS', '탁구', Icons.sports_tennis),
    ('TENNIS', '테니스', Icons.sports_tennis),
    ('BADMINTON', '배드민턴', Icons.sports_tennis),
    ('BOWLING', '볼링', Icons.sports),
    ('BILLIARDS', '당구', Icons.circle_outlined),
    ('ROCK_PAPER_SCISSORS', '가위바위보', Icons.pan_tool_rounded),
    ('ARM_WRESTLING', '팔씨름', Icons.fitness_center),
    ('COIN_TOSS', '동전던지기', Icons.monetization_on_rounded),
  ];

  void _updateGHandicap(double value) {
    setState(() {
      _gHandicap = value;
      _gHandiController.text = value.toStringAsFixed(1);
    });
  }

  void _updateGHandicapFromText(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      setState(() {
        _gHandicap = parsed.clamp(0, 54);
      });
    }
  }

  Future<void> _submit() async {
    if (_displayNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필 이름을 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.createSportsProfile(
        sportType: _selectedSport,
        displayName: _displayNameController.text.trim(),
        gHandicap: _selectedSport == 'GOLF' ? _gHandicap : null,
      );

      if (mounted) context.go(AppRoutes.locationSetup);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _gHandiController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('스포츠 프로필'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 진행 표시 바 (2/3)
            _buildStepIndicator(),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '2단계: 스포츠 프로필',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
                Text(
                  '2 / 3',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            const Text(
              '어떤 스포츠를\n즐기시나요?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '주력 종목을 선택해주세요. 나중에 추가할 수 있어요.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),

            const SizedBox(height: 24),

            // 종목 선택 그리드 (2열)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: _sports.map((sport) {
                final isSelected = _selectedSport == sport.$1;
                return _SportCard(
                  key: ValueKey(sport.$1),
                  sportKey: sport.$1,
                  name: sport.$2,
                  icon: sport.$3,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedSport = sport.$1),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // 프로필 이름
            const Text(
              '프로필 이름',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameController,
              maxLength: 20,
              decoration: const InputDecoration(
                hintText: '예: 주말 골퍼',
                counterText: '',
              ),
            ),

            // G핸디 입력 (골프만)
            if (_selectedSport == 'GOLF') ...[
              const SizedBox(height: 24),

              Row(
                children: [
                  const Text(
                    '골프존 G핸디',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '선택',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '정확한 매칭을 위해 입력해주세요.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),

              // Slider + 현재 값 표시
              AdaptiveSlider(
                value: _gHandicap / 54,
                min: 0.0,
                max: 1.0,
                onChanged: (value) => _updateGHandicap(value * 54),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _gHandiController
                  ..text = _gHandicap.toStringAsFixed(1),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: '0.0 ~ 54.0',
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                onChanged: _updateGHandicapFromText,
              ),
            ],

            const SizedBox(height: 48),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '다음',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(
        3,
        (i) => Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            height: 5,
            decoration: BoxDecoration(
              color: i < 2
                  ? AppTheme.primaryColor
                  : const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

/// 종목 선택 카드
class _SportCard extends StatelessWidget {
  final String sportKey;
  final String name;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SportCard({
    super.key,
    required this.sportKey,
    required this.name,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.08)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // 체크마크 (선택 시)
            if (isSelected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            // 내용
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 28,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
