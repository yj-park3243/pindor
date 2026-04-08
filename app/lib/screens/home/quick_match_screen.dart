import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/pin_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../screens/profile/profile_screen.dart';
import '../../repositories/matching_repository.dart';

/// "오늘 대결 나가고 싶다" 즉시 매칭 화면
/// 즐겨찾기 핀이 기본 선택, 종목도 기본값 적용
class QuickMatchScreen extends ConsumerStatefulWidget {
  const QuickMatchScreen({super.key});

  @override
  ConsumerState<QuickMatchScreen> createState() => _QuickMatchScreenState();
}

class _QuickMatchScreenState extends ConsumerState<QuickMatchScreen> {
  bool _isLoading = false;
  late String _selectedSport;
  Pin? _selectedPin;
  DateTime _availableUntil = DateTime.now().add(const Duration(hours: 4));
  int _selectedTimeOption = 1;

  static const _timeOptions = [
    ('2시간 후까지', Duration(hours: 2)),
    ('4시간 후까지', Duration(hours: 4)),
    ('6시간 후까지', Duration(hours: 6)),
    ('오늘 자정까지', null),
  ];

  @override
  void initState() {
    super.initState();
    _selectedSport = ref.read(sportPreferenceProvider);
    _selectedPin = ref.read(selectedPinProvider);
  }

  Future<void> _createInstantMatch() async {
    if (_selectedPin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('핀을 선택해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.createInstantMatch({
        'sportType': _selectedSport,
        'pinId': _selectedPin!.id,
        'availableUntil': _availableUntil.toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('즉시 매칭 요청이 등록되었습니다!'),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );
        context.go(AppRoutes.matchList);
      }
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
  Widget build(BuildContext context) {
    final pinsAsync = ref.watch(allPinsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('오늘 대결 나가고 싶다'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt, color: AppTheme.primaryColor, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '핀과 종목을 선택하면 주변 상대를 즉시 탐색합니다.',
                      style: TextStyle(fontSize: 13, color: AppTheme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ─── 핀 선택 ───
            const Text('핀 선택',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),

            // 선택된 핀 표시
            if (_selectedPin != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedPin!.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    const Icon(Icons.check_circle, size: 18, color: AppTheme.primaryColor),
                  ],
                ),
              ),

            // 핀 목록 (가로 스크롤 칩)
            pinsAsync.when(
              loading: () => const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => const Text('핀 목록을 불러올 수 없습니다.',
                  style: TextStyle(color: AppTheme.textSecondary)),
              data: (pins) {
                final dongPins = pins.where((p) => p.level == 'DONG').toList();
                return SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: dongPins.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final pin = dongPins[index];
                      final isSelected = _selectedPin?.id == pin.id;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedPin = pin),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryColor : const Color(0xFFF0F2F5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppTheme.primaryColor : const Color(0xFFE0E3E8),
                            ),
                          ),
                          child: Text(
                            pin.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // ─── 종목 선택 ───
            const Text('종목 선택',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allSports.map((sport) {
                final isSelected = _selectedSport == sport.value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSport = sport.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sport.icon,
                            size: 16,
                            color: isSelected ? Colors.white : AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          sport.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isSelected ? Colors.white : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // ─── 가능 시간대 ───
            const Text('가능 시간대',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_timeOptions.length, (index) {
                final option = _timeOptions[index];
                final isSelected = _selectedTimeOption == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTimeOption = index;
                      if (option.$2 != null) {
                        _availableUntil = DateTime.now().add(option.$2!);
                      } else {
                        final now = DateTime.now();
                        _availableUntil = DateTime(now.year, now.month, now.day, 23, 59);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      option.$1,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 8),
            Text(
              '~${_availableUntil.hour.toString().padLeft(2, '0')}:${_availableUntil.minute.toString().padLeft(2, '0')} 까지 매칭 탐색',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),

            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _createInstantMatch,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.bolt),
                label: const Text('즉시 매칭 요청', style: TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
