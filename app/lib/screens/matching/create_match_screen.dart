import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../core/network/api_client.dart';
import '../../providers/sport_preference_provider.dart';
import '../../providers/matching_provider.dart';
import '../../widgets/common/app_toast.dart';

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
  bool _sportExpanded = false;

  // 오늘 날짜에 이미 WAITING 요청이 있으면 true (날짜 선택 제한용)
  bool _hasTodayWaiting = false;

  // 성별 조건
  String _genderPreference = 'ANY';

  // 친선 모드 (false = 랭크, true = 친선)
  bool _isCasual = false;

  // 나이 범위 (친선 모드에서만)
  bool _useAgeFilter = false;
  double _ageRange = 5; // 0~10 (±N세)

  // (value, label, subLabel, slotStartHour) — cutoff: 오늘이면 slotStartHour - 1시 이후 비활성화
  static const _timeSlots = [
    ('DAWN', '새벽', '0~3시', 0),
    ('EARLY_MORNING', '이른 아침', '3~6시', 3),
    ('MORNING', '오전', '6~9시', 6),
    ('LATE_MORNING', '오전 늦게', '9~12시', 9),
    ('AFTERNOON', '오후', '12~15시', 12),
    ('LATE_AFTERNOON', '오후 늦게', '15~18시', 15),
    ('EVENING', '저녁', '18~21시', 18),
    ('NIGHT', '밤', '21~24시', 21),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // 밤 11시 이후면 기본 날짜를 내일로 설정
    _selectedDate = now.hour >= 23 ? now.add(const Duration(days: 1)) : now;
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final firstDate = (_hasTodayWaiting || now.hour >= 23) ? tomorrow : today;
    final initial = _selectedDate.isBefore(firstDate) ? firstDate : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: tomorrow,
      locale: const Locale('ko'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        if (picked.year == now.year && picked.month == now.month && picked.day == now.day) {
          final slot = _timeSlots.where((s) => s.$1 == _selectedTimeSlot).firstOrNull;
          if (slot != null && now.hour >= slot.$4 + 2) {
            _selectedTimeSlot = 'ANY';
          }
        }
      });
    }
  }

  /// 매칭 신청 확인 다이얼로그 — 정보 카드 형식 (핀/종목/날짜/시간)
  Future<bool?> _showConfirmDialog() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final diffDays = picked.difference(today).inDays;
    final dateLabel = diffDays == 0
        ? '오늘 (${_selectedDate.month}/${_selectedDate.day})'
        : diffDays == 1
            ? '내일 (${_selectedDate.month}/${_selectedDate.day})'
            : diffDays == 2
                ? '모레 (${_selectedDate.month}/${_selectedDate.day})'
                : '${_selectedDate.month}월 ${_selectedDate.day}일';

    // 시간대 라벨
    String timeRange;
    if (_selectedTimeSlot == 'ANY') {
      timeRange = '아무 때나';
    } else {
      final slot = _timeSlots.where((s) => s.$1 == _selectedTimeSlot).firstOrNull;
      timeRange = slot != null ? '${slot.$2} (${slot.$3})' : _selectedTimeSlot;
    }

    final modeLabel = _isCasual ? '친선' : '랭크';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 타이틀
              const Text(
                '매칭 요청 확인',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '아래 조건으로 매칭을 시작합니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              // 정보 카드
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2E2E)),
                ),
                child: Column(
                  children: [
                    _confirmRow(Icons.location_on_rounded, '장소', _pinName ?? '-'),
                    const _ConfirmDivider(),
                    _confirmRow(sportIcon(_selectedSport), '종목',
                        '${sportLabel(_selectedSport)} · $modeLabel'),
                    const _ConfirmDivider(),
                    _confirmRow(Icons.calendar_today_rounded, '날짜', dateLabel),
                    const _ConfirmDivider(),
                    _confirmRow(Icons.access_time_rounded, '시간', timeRange),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // 버튼
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        backgroundColor: const Color(0xFF2A2A2A),
                      ),
                      child: const Text('취소',
                          style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        backgroundColor: AppTheme.primaryColor,
                      ),
                      child: const Text('매칭 시작',
                          style: TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_pinId == null) {
      AppToast.info('핀 탭에서 핀을 선택한 후 매칭을 신청해주세요');
      return;
    }

    // 밤 11시 이후 당일 매칭 차단
    final now = DateTime.now();
    final isSelectedToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (isSelectedToday && now.hour >= 23) {
      AppToast.warning('밤 11시 이후에는 당일 매칭 요청을 할 수 없습니다.');
      return;
    }

    // 확인 다이얼로그 — 오늘/내일 + 시간대 + 종목 명확히 노출
    final confirmed = await _showConfirmDialog();
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      // notifier를 통해 요청 생성 → 자동으로 matchRequestProvider 갱신
      final body = {
        'sportType': _selectedSport,
        'requestType': 'SCHEDULED',
        'desiredDate':
            '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
        'desiredTimeSlot': _selectedTimeSlot,
        'pinId': _pinId,
        'genderPreference': _genderPreference,
        'isCasual': _isCasual,
      };

      // 친선 + 나이 필터 사용 시: ageRange를 서버에 전달
      // 서버에서 내 birthDate 기반으로 minAge/maxAge 자동 계산
      if (_isCasual && _useAgeFilter) {
        body['ageRange'] = _ageRange.toInt();
      }

      debugPrint('[Match] 매칭 잡기 시작 — sport=$_selectedSport pin=$_pinId date=${body['desiredDate']} slot=$_selectedTimeSlot gender=$_genderPreference casual=$_isCasual');
      final request = await ref.read(matchRequestProvider.notifier).createRequest(body);
      debugPrint('[Match] 매칭 요청 응답 — requestId=${request.id} status=${request.status}');

      if (mounted) {
        if (request.status == 'MATCHED') {
          AppToast.success('매칭 상대를 찾았습니다!');

          // 1순위: 서버 응답의 matchedMatchId로 즉시 이동 (가장 안정적)
          if (request.matchedMatchId != null && request.matchedMatchId!.isNotEmpty) {
            debugPrint('[Match] 즉시 매칭 — 응답 matchedMatchId=${request.matchedMatchId}');
            context.go('/matches/${request.matchedMatchId}/accept');
          } else {
            // 2순위 fallback: 소켓/polling으로 PENDING_ACCEPT 매칭 조회
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              ref.invalidate(pendingAcceptMatchesProvider);
              final matches = await ref.read(pendingAcceptMatchesProvider.future);
              if (mounted && matches.isNotEmpty) {
                debugPrint('[Match] 즉시 매칭 — fallback 이동 matchId=${matches.first.id}');
                context.go('/matches/${matches.first.id}/accept');
              } else if (mounted) {
                debugPrint('[Match] 즉시 매칭 — pending 없음, 목록으로 이동');
                context.go(AppRoutes.matchList);
              }
            }
          }
        } else {
          // 매칭 요청 등록됨 → 소켓 연결 (MATCH_FOUND 수신 필요)
          debugPrint('[Match] 매칭 대기 등록 — 목록 화면 이동');
          unawaited(syncSocketConnection(ref));
          context.go(AppRoutes.matchList);
          Future.delayed(const Duration(milliseconds: 300), () {
            AppToast.success('매칭 요청이 등록되었습니다!');
          });
        }
      }
    } catch (e) {
      debugPrint('[Match] 매칭 요청 실패: $e');
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '매칭 요청에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 활성 매칭/요청 수 계산: WAITING 요청 + CHAT/CONFIRMED 매칭
    final requestState = ref.watch(matchRequestProvider);
    final matchListAsync = ref.watch(matchListProvider(null));
    final waitingCount =
        requestState.valueOrNull?.sent.where((r) => r.isWaiting).length ?? 0;
    final activeMatchCount = matchListAsync.valueOrNull
            ?.where((m) => m.isChat || m.isConfirmed)
            .length ??
        0;
    final totalActiveCount = waitingCount + activeMatchCount;
    final isFull = totalActiveCount >= 2;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // 오늘 날짜에 이미 WAITING 요청이 있으면 선택 가능한 최소 날짜를 내일로 제한
    final hasTodayWaiting = requestState.valueOrNull?.sent.any((r) {
          if (!r.isWaiting) return false;
          final d = r.desiredDate;
          if (d == null) return false;
          try {
            final date = DateTime.parse(d);
            return date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;
          } catch (_) {
            return false;
          }
        }) ??
        false;

    // _hasTodayWaiting 상태 동기화 (빌드 후 setState 방지위해 addPostFrameCallback 사용)
    if (_hasTodayWaiting != hasTodayWaiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _hasTodayWaiting = hasTodayWaiting);
      });
    }

    // 오늘에 이미 요청이 있고 선택 날짜가 오늘이면 내일로 자동 보정
    if (hasTodayWaiting) {
      final isCurrentToday = _selectedDate.year == today.year &&
          _selectedDate.month == today.month &&
          _selectedDate.day == today.day;
      if (isCurrentToday) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedDate = tomorrow);
        });
      }
    }

    final dateStr =
        '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일';
    final isToday = _selectedDate.day == now.day &&
        _selectedDate.month == now.month &&
        _selectedDate.year == now.year;
    final isTomorrow = _selectedDate.day == tomorrow.day &&
        _selectedDate.month == tomorrow.month &&
        _selectedDate.year == tomorrow.year;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('매칭 요청'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // ─── 매칭 2개 꽉 찼을 때 안내 배너 ───
            if (isFull)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '매칭이 2개 잡혀있습니다. 완료 또는 취소 후 다시 신청하세요.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

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

            // ─── 1. 종목 선택 (아코디언) ───
            _SectionCard(
              stepNumber: 1,
              title: '종목 선택',
              icon: Icons.sports_score_rounded,
              child: Column(
                children: [
                  // 현재 선택된 종목 (탭하면 펼침/접기)
                  GestureDetector(
                    onTap: () => setState(() => _sportExpanded = !_sportExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(sportIcon(_selectedSport), size: 22, color: AppTheme.primaryColor),
                          const SizedBox(width: 10),
                          Text(
                            sportLabel(_selectedSport),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _sportExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.expand_more, color: AppTheme.primaryColor),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 펼쳐진 종목 그리드 (열림: 아래로 펼침, 닫힘: 위로 슬라이드+스케일 축소)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: _sportExpanded ? Curves.easeOutBack : Curves.fastOutSlowIn,
                    alignment: Alignment.topCenter,
                    child: _sportExpanded
                        ? TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - value) * -20),
                                child: child,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: GridView.count(
                                crossAxisCount: 4,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.9,
                                children: allSports.map((sport) {
                                  final isSelected = _selectedSport == sport.value;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedSport = sport.value;
                                      _sportExpanded = false;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppTheme.primaryColor.withValues(alpha: 0.15)
                                            : const Color(0xFF2A2A2A),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(sport.icon, size: 24, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary),
                                          const SizedBox(height: 4),
                                          Text(
                                            sport.label,
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                              fontSize: 11,
                                              color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
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
                  Switch.adaptive(
                    value: !_isCasual,
                    onChanged: (v) => setState(() {
                      _isCasual = !v;
                      // 랭크로 전환 시 친선 전용 옵션(OPPOSITE) 자동 리셋
                      if (!_isCasual && _genderPreference == 'OPPOSITE') {
                        _genderPreference = 'ANY';
                      }
                    }),
                    activeColor: AppTheme.primaryColor,
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
                          Text.rich(
                            TextSpan(
                              text: dateStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              children: [
                                if (isToday)
                                  const TextSpan(
                                    text: ' (오늘)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                if (isTomorrow)
                                  const TextSpan(
                                    text: ' (내일)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
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
                  // 3시간 단위 시간대 그리드 (4열)
                  Builder(builder: (context) {
                    final now = DateTime.now();
                    final isToday = _selectedDate.year == now.year &&
                        _selectedDate.month == now.month &&
                        _selectedDate.day == now.day;

                    return Column(
                      children: [
                        GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1.6,
                          children: _timeSlots.map((slot) {
                            final isSelected = _selectedTimeSlot == slot.$1;
                            // cutoff: 슬롯 종료 1시간 전 이후면 비활성화 (예: 9~12시 → 11시부터 비활성화)
                            final isPast = isToday && now.hour >= slot.$4 + 2;
                            return GestureDetector(
                              onTap: isPast
                                  ? null
                                  : () => setState(() => _selectedTimeSlot = slot.$1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: isPast
                                      ? const Color(0xFF2A2A2A)
                                      : isSelected
                                          ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                          : const Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected && !isPast
                                        ? AppTheme.primaryColor
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      slot.$2,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: isPast
                                            ? AppTheme.textDisabled
                                            : isSelected
                                                ? AppTheme.primaryColor
                                                : AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      slot.$3,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isPast
                                            ? AppTheme.textDisabled
                                            : const Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 6),
                        // 하루종일 버튼 (가로 전체)
                        GestureDetector(
                          onTap: () => setState(() => _selectedTimeSlot = 'ANY'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTimeSlot == 'ANY'
                                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                  : const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedTimeSlot == 'ANY'
                                    ? AppTheme.primaryColor
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '하루종일',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: _selectedTimeSlot == 'ANY'
                                      ? AppTheme.primaryColor
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── 4. 성별 조건 ───
            _SectionCard(
              stepNumber: 4,
              title: '상대 성별 조건',
              icon: Icons.people_alt_rounded,
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEFF1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _genderPreference = 'ANY'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: _genderPreference == 'ANY'
                                ? AppTheme.primaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _genderPreference == 'ANY'
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryColor
                                          .withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '상관없음',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _genderPreference == 'ANY'
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _genderPreference == 'ANY'
                                  ? Colors.white
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _genderPreference = 'SAME'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: _genderPreference == 'SAME'
                                ? AppTheme.primaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _genderPreference == 'SAME'
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryColor
                                          .withOpacity(0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '같은 성별만',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _genderPreference == 'SAME'
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _genderPreference == 'SAME'
                                  ? Colors.white
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // OPPOSITE은 친선 매칭에서만 노출 — 랭크는 점수 기반이라 이성 필터링 의도 없음
                    if (_isCasual)
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _genderPreference = 'OPPOSITE'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: _genderPreference == 'OPPOSITE'
                                  ? AppTheme.primaryColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _genderPreference == 'OPPOSITE'
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryColor
                                            .withOpacity(0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '이성만',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _genderPreference == 'OPPOSITE'
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _genderPreference == 'OPPOSITE'
                                    ? Colors.white
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ─── 5. 나이 범위 (친선 모드에서만) ───
            if (_isCasual) ...[
              const SizedBox(height: 12),
              _SectionCard(
                stepNumber: 5,
                title: '나이 범위',
                icon: Icons.people_alt_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _useAgeFilter
                                ? '내 나이 ±${_ageRange.toInt()}세까지'
                                : '나이 상관없음',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _useAgeFilter
                                  ? AppTheme.primaryColor
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: _useAgeFilter,
                          onChanged: (v) => setState(() => _useAgeFilter = v),
                          activeColor: AppTheme.primaryColor,
                        ),
                      ],
                    ),
                    if (_useAgeFilter) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(8, (i) {
                          final val = i.toDouble();
                          final isSelected = _ageRange == val;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _ageRange = val),
                              child: Container(
                                margin: EdgeInsets.only(right: i < 7 ? 4 : 0),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : const Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  i == 0 ? '동갑' : '±$i',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '* 휴대폰 인증 후 나이 정보가 등록되면 적용됩니다',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDisabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // 요청 버튼 (하단 고정)
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0A0A),
              border: Border(
                top: BorderSide(color: Color(0xFF1E1E1E), width: 1),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: (_isLoading || isFull) ? null : _submit,
                style: isFull
                    ? ElevatedButton.styleFrom(
                        disabledBackgroundColor: const Color(0xFF333333),
                      )
                    : null,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        isFull ? '매칭이 2개 잡혀있습니다' : '매칭 요청하기',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ),
        ],
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
        color: const Color(0xFF1E1E1E),
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

class _ConfirmDivider extends StatelessWidget {
  const _ConfirmDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFF2A2A2A),
    );
  }
}
