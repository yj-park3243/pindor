import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/router.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../providers/sport_preference_provider.dart';
import '../../repositories/matching_repository.dart';

/// 매칭 요청 생성 화면
/// 핀 탭에서 핀 선택 후 진입 — pinId, sportType은 쿼리 파라미터로 받음
class CreateMatchScreen extends ConsumerStatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  ConsumerState<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends ConsumerState<CreateMatchScreen> {
  late String _selectedSport;
  late DateTime _selectedDate;
  String _selectedTimeSlot = 'ANY';
  bool _isLoading = false;

  String? _pinId;
  String? _pinName;

  // 성별 조건
  String _genderPreference = 'ANY';

  // 친선 모드 (false = 랭크, true = 친선)
  bool _isCasual = false;

  static const _timeSlots = [
    ('DAWN', '새벽', '6시까지'),
    ('MORNING', '오전', '12시까지'),
    ('AFTERNOON', '오후', '18시까지'),
    ('EVENING', '저녁', '23시까지'),
    ('ANY', '하루종일', '24시까지'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now(); // 기본값 오늘
    _selectedSport = ref.read(sportPreferenceProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    _pinId = uri.queryParameters['pinId'];
    _pinName = uri.queryParameters['pinName'];
    final sportParam = uri.queryParameters['sportType'];
    if (sportParam != null && sportParam.isNotEmpty) {
      _selectedSport = sportParam;
    }
    final casualParam = uri.queryParameters['casual'];
    if (casualParam == 'true' && !_isCasual) {
      _isCasual = true;
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _submit() async {
    if (_pinId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('핀 탭에서 핀을 선택한 후 매칭을 신청해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.createMatchRequest({
        'sportType': _selectedSport,
        'requestType': 'SCHEDULED',
        'desiredDate':
            '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
        'desiredTimeSlot': _selectedTimeSlot,
        'pinId': _pinId,
        'genderPreference': _genderPreference,
        'isCasual': _isCasual,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('매칭 요청이 등록되었습니다!'),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );
        context.go(AppRoutes.matchList);
      }
    } catch (e) {
      if (mounted) {
        // Dio 에러에서 서버 메시지 추출, 없으면 기본 메시지 표시
        String errorMessage = '매칭 요청에 실패했습니다.';
        if (e is DioException) {
          final data = e.response?.data;
          if (data is Map<String, dynamic> && data['error'] != null) {
            final errorData = data['error'] as Map<String, dynamic>;
            errorMessage = errorData['message']?.toString() ?? errorMessage;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일';
    final isToday = _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('매칭 요청'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 핀 정보 (읽기전용) ───
            if (_pinName != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _pinName!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // ─── 1. 종목 선택 ───
            _SectionCard(
              stepNumber: 1,
              title: '종목 선택',
              icon: Icons.sports_score_rounded,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allSports.map((sport) {
                  final isSelected = _selectedSport == sport.value;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedSport = sport.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sport.icon,
                              size: 16,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            sport.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // ─── 2. 매칭 모드 ───
            _SectionCard(
              stepNumber: 2,
              title: '매칭 모드',
              icon: Icons.tune_rounded,
              child: Row(
                children: [
                  Icon(
                    _isCasual ? Icons.handshake_outlined : Icons.leaderboard,
                    size: 18,
                    color: _isCasual ? Colors.orange : AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isCasual ? '친선 (점수 미반영)' : '랭크 (점수 반영)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _isCasual ? Colors.orange : AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  AdaptiveSwitch(
                    value: _isCasual,
                    onChanged: (v) => setState(() => _isCasual = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── 3. 날짜/시간 ───
            _SectionCard(
              stepNumber: 3,
              title: '날짜 및 시간',
              icon: Icons.calendar_today_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_rounded,
                              size: 20, color: AppTheme.primaryColor),
                          const SizedBox(width: 10),
                          Text(
                            '$dateStr${isToday ? " (오늘)" : ""}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right,
                              size: 18, color: AppTheme.textDisabled),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '희망 시간대',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _timeSlots.map((slot) {
                      final isSelected = _selectedTimeSlot == slot.$1;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedTimeSlot = slot.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                slot.$2,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                slot.$3,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textDisabled,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── 4. 성별 조건 ───
            _SectionCard(
              stepNumber: 4,
              title: '상대 성별 조건',
              icon: Icons.people_alt_rounded,
              child: AdaptiveSegmentedControl(
                labels: const ['상관없음', '같은 성별만'],
                selectedIndex: _genderPreference == 'ANY' ? 0 : 1,
                onValueChanged: (index) => setState(
                    () => _genderPreference = index == 0 ? 'ANY' : 'SAME'),
              ),
            ),

            const SizedBox(height: 24),

            // 요청 버튼
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
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('매칭 요청하기',
                        style: TextStyle(fontSize: 16)),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final int stepNumber;
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.stepNumber,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$stepNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 18, color: AppTheme.textPrimary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
