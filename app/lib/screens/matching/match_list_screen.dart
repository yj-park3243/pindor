import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/sports.dart' as sports_config;
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../models/match_request.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../providers/matching_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/matching_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';
import '../../widgets/common/user_avatar.dart';
import '../../widgets/common/score_display.dart';
import '../../providers/chat_provider.dart';
import '../../core/network/socket_service.dart';
import 'package:bottom_picker/bottom_picker.dart';


/// 매칭 목록 화면 (PRD SCREEN-020)
/// 전체 매칭을 한 화면에 통합: 진행중 우선 → 날짜 최신순
/// PENDING_ACCEPT 상태 매칭이 있으면 MatchAcceptScreen으로 리다이렉트
class MatchListScreen extends ConsumerStatefulWidget {
  final int initialTab; // 하위 호환성 유지 (현재 사용 안 함)

  const MatchListScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends ConsumerState<MatchListScreen> {
  bool _redirectedToAccept = false; // 무한 루프 방지 가드
  final Set<String> _joinedMatchRooms = {};

  // 검색 필터
  bool _showFilters = false;
  String? _filterSport; // null = 전체
  String? _filterPin; // null = 전체
  String _filterPeriod = 'ALL'; // ALL, TODAY, WEEK, MONTH
  String _filterSort = 'NEWEST'; // NEWEST, OLDEST

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 서버에서 강제 갱신 (캐시 무시)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(matchListForceRefreshProvider.notifier).state = true;
      ref.invalidate(matchListProvider(null));
      ref.invalidate(matchRequestProvider);
    });
  }

  /// 활성 상태(PENDING_ACCEPT, CHAT, CONFIRMED)의 매칭 룸에 소켓 입장
  void _joinActiveMatchRooms() {
    final matches = ref.read(matchListProvider(null)).valueOrNull;
    if (matches == null) return;

    for (final match in matches) {
      final status = match.status;
      if (status == 'PENDING_ACCEPT' || status == 'CHAT' || status == 'CONFIRMED') {
        if (!_joinedMatchRooms.contains(match.id)) {
          _joinedMatchRooms.add(match.id);
          SocketService.instance.joinMatch(match.id);
        }
      }
    }
  }

  @override
  void dispose() {
    // 소켓 룸 명시적 퇴장 후 클리어 (메모리 누수 방지)
    for (final matchId in _joinedMatchRooms) {
      SocketService.instance.leaveMatch(matchId);
    }
    _joinedMatchRooms.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allMatchesAsync = ref.watch(matchListProvider(null));

    // 매칭 목록 로드 완료 시 활성 매칭 룸 조인 (소켓 이벤트 처리는 main_tab_screen에서 담당)
    ref.listen(matchListProvider(null), (prev, next) {
      if (next.hasValue) _joinActiveMatchRooms();
    });

    // PENDING_ACCEPT 중 내가 아직 수락 안 한 매칭만 잠금 대상
    final myId = ref.watch(currentUserProvider)?.id;
    final pendingMatches = allMatchesAsync.valueOrNull
            ?.where((m) {
              if (!m.isPendingAccept) return false;
              // 내가 이미 수락했으면 잠금 대상에서 제외
              // myAcceptance는 userId 없이 내려올 수 있으므로 accepted만 체크
              if (m.acceptances != null) {
                final anyAccepted = m.acceptances!.any((a) => a.accepted == true);
                if (anyAccepted) return false;
              }
              return true;
            })
            .toList() ??
        [];
    final hasPending = pendingMatches.isNotEmpty;

    // PENDING_ACCEPT 매칭이 있으면 MatchAcceptScreen으로 이동 (무한 루프 방지)
    if (hasPending && !_redirectedToAccept) {
      _redirectedToAccept = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/matches/${pendingMatches.first.id}/accept');
        }
      });
    }
    // 새로운 PENDING_ACCEPT 감지 시 가드 리셋
    if (!hasPending) {
      _redirectedToAccept = false;
    }

    final requestsAsync = ref.watch(matchRequestProvider);
    final waitingRequests =
        requestsAsync.valueOrNull?.sent.where((r) => r.isWaiting).toList() ?? [];
    final waitingCount = waitingRequests.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('매칭'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _showFilters ? Icons.search_off : Icons.search,
              color: _showFilters ? AppTheme.primaryColor : AppTheme.textSecondary,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
        ],
      ),
      body: Column(
        children: [
          // 매칭 규칙 안내 배너
          _MatchRuleInfoBanner(),
          // 검색 필터 패널
          if (_showFilters) _buildFilterPanel(context),
          Expanded(child: allMatchesAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(
          message: '매칭 목록을 불러올 수 없습니다.',
          onRetry: () {
            ref.invalidate(matchListProvider(null));
            ref.invalidate(matchRequestProvider);
          },
        ),
        data: (matchList) {
          // 진행중(CHAT/CONFIRMED/PENDING_ACCEPT) 매칭 + 완료/취소된 매칭 포함한 정렬
          // - CHAT, CONFIRMED, 내가 수락한 PENDING_ACCEPT만 화면에 표시 (진행중 그룹)
          // - COMPLETED / CANCELLED도 날짜 최신순으로 그 뒤에 표시
          final filteredList = matchList.where((m) {
            if (m.isChat || m.isConfirmed) return true;
            // 내가 수락 완료한 PENDING_ACCEPT (상대 응답 대기 중)도 표시
            if (m.isPendingAccept &&
                m.acceptances?.any((a) => a.accepted == true) == true) return true;
            // 취소된 매칭은 숨김
            if (m.isCancelled) return false;
            // 완료된 매칭만 표시
            if (m.isCompleted || m.isCancelled) return true;
            return false;
          }).toList();

          // 검색 필터 적용
          var filtered2 = [...filteredList];
          if (_filterSport != null) {
            filtered2 = filtered2.where((m) => m.sportType == _filterSport).toList();
          }
          if (_filterPin != null) {
            filtered2 = filtered2.where((m) => m.pinName == _filterPin).toList();
          }
          if (_filterPeriod != 'ALL') {
            final now = DateTime.now();
            final cutoff = _filterPeriod == 'TODAY'
                ? DateTime(now.year, now.month, now.day)
                : _filterPeriod == 'WEEK'
                    ? now.subtract(const Duration(days: 7))
                    : now.subtract(const Duration(days: 30));
            filtered2 = filtered2.where((m) => m.createdAt.isAfter(cutoff)).toList();
          }

          // 정렬: 진행중 매칭(CHAT/CONFIRMED/PENDING_ACCEPT) → 완료/취소
          final sorted = [...filtered2];
          sorted.sort((a, b) {
            final aActive = a.isChat || a.isConfirmed || a.isPendingAccept;
            final bActive = b.isChat || b.isConfirmed || b.isPendingAccept;
            if (aActive && !bActive) return -1;
            if (!aActive && bActive) return 1;
            return _filterSort == 'NEWEST'
                ? b.createdAt.compareTo(a.createdAt)
                : a.createdAt.compareTo(b.createdAt);
          });

          // 3단 분리: 진행중 매칭 → 대기 요청 → 완료된 매칭
          final activeMatches = sorted.where((m) => m.isChat || m.isConfirmed || m.isPendingAccept).toList();
          final completedMatches = sorted.where((m) => !m.isChat && !m.isConfirmed && !m.isPendingAccept).toList();

          // 빈 상태: 매칭도 없고 대기 요청도 없는 경우
          if (sorted.isEmpty && waitingCount == 0) {
            // matchRequestProvider 아직 로딩 중이면 로딩 표시
            if (requestsAsync.isLoading) return const FullScreenLoading();

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.push_pin_rounded,
                        size: 36,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '매칭이 없어요',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '핀에서 매칭을 잡아보세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () => context.go(AppRoutes.map),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text(
                        '매칭 잡으러 가기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // 대기 요청만 있고 매칭 목록이 비어있는 경우
          if (sorted.isEmpty && waitingCount > 0) {
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                ...waitingRequests.map((req) => _WaitingRequestCard(request: req)),
              ],
            );
          }

          // 진행중 매칭 → 대기 요청 → 완료된 매칭
          final totalItems = activeMatches.length + waitingCount + completedMatches.length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(matchListProvider(null));
              ref.invalidate(matchRequestProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 100),
              itemCount: totalItems,
              itemBuilder: (context, index) {
                // 1) 진행중 매칭
                if (index < activeMatches.length) {
                  final match = activeMatches[index];
                  return _MatchListTile(
                    match: match,
                    onTap: () => context.go('${AppRoutes.matchList}/${match.id}'),
                  );
                }
                // 2) 대기 요청
                final afterActive = index - activeMatches.length;
                if (afterActive < waitingCount) {
                  return _WaitingRequestCard(request: waitingRequests[afterActive]);
                }
                // 3) 완료된 매칭
                final completedIndex = afterActive - waitingCount;
                final match = completedMatches[completedIndex];
                return _MatchListTile(
                  match: match,
                  onTap: () => context.go('${AppRoutes.matchList}/${match.id}'),
                );
              },
            ),
          );
        },
      )),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    final matches = ref.read(matchListProvider(null)).valueOrNull ?? [];
    final sportTypes = matches.map((m) => m.sportType).toSet().toList()..sort();
    final pinNames = matches.where((m) => m.pinName != null).map((m) => m.pinName!).toSet().toList()..sort();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          // 종목 드롭다운
          Expanded(
            child: _buildDropdown(
              icon: Icons.sports_rounded,
              value: _filterSport == null ? '전체 종목' : sports_config.sportLabel(_filterSport!),
              onTap: () => _showSelectSheet(
                context,
                title: '종목 선택',
                items: [null, ...sportTypes],
                labelBuilder: (v) => v == null ? '전체 종목' : sports_config.sportLabel(v),
                selected: _filterSport,
                onSelected: (v) => setState(() => _filterSport = v),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 핀 드롭다운
          Expanded(
            child: _buildDropdown(
              icon: Icons.location_on_outlined,
              value: _filterPin ?? '전체 핀',
              onTap: () => _showSelectSheet(
                context,
                title: '핀 선택',
                items: [null, ...pinNames],
                labelBuilder: (v) => v ?? '전체 핀',
                selected: _filterPin,
                onSelected: (v) => setState(() => _filterPin = v),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 기간 드롭다운
          _buildDropdown(
            icon: Icons.calendar_today_rounded,
            value: _filterPeriod == 'ALL' ? '전체' : _filterPeriod == 'TODAY' ? '오늘' : _filterPeriod == 'WEEK' ? '주간' : '월간',
            compact: true,
            onTap: () => _showSelectSheet(
              context,
              title: '기간 선택',
              items: ['ALL', 'TODAY', 'WEEK', 'MONTH'],
              labelBuilder: (v) => v == 'ALL' ? '전체' : v == 'TODAY' ? '오늘' : v == 'WEEK' ? '이번 주' : '이번 달',
              selected: _filterPeriod,
              onSelected: (v) => setState(() => _filterPeriod = v ?? 'ALL'),
            ),
          ),
          const SizedBox(width: 8),

          // 정렬 토글
          GestureDetector(
            onTap: () => setState(() => _filterSort = _filterSort == 'NEWEST' ? 'OLDEST' : 'NEWEST'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _filterSort == 'NEWEST' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                size: 16,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required IconData icon,
    required String value,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            if (!compact) Expanded(
              child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            ) else Text(value, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 14, color: AppTheme.textDisabled),
          ],
        ),
      ),
    );
  }

  void _showSelectSheet<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T) labelBuilder,
    required T selected,
    required void Function(T) onSelected,
  }) {
    final selectedIndex = items.indexOf(selected).clamp(0, items.length - 1);

    BottomPicker(
      items: items.map((item) => Text(
        labelBuilder(item),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
      )).toList(),
      selectedItemIndex: selectedIndex,
      backgroundColor: const Color(0xFF1E1E1E),
      headerBuilder: (_) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      buttonSingleColor: AppTheme.primaryColor,
      buttonContent: const Center(
        child: Text('선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      pickerTextStyle: const TextStyle(fontSize: 16, color: Colors.white),
      onSubmit: (index) {
        onSelected(items[index]);
      },
      dismissable: true,
    ).show(context);
  }
}


/// 매칭 대기 중 배너 — 2줄 간단 표시
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor.withValues(alpha: 0.2) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: selected ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.5)) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppTheme.primaryColor : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchingWaitingBanner extends StatelessWidget {
  final int waitingCount;

  const _MatchingWaitingBanner({required this.waitingCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          LoadingAnimationWidget.beat(
            color: AppTheme.primaryColor,
            size: 18,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '매칭 대기 중 ($waitingCount건)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Text(
                '상대를 찾고 있습니다...',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 대기 중인 매칭 요청 카드 (핀 이름, 종목, 시간대, 취소 버튼 포함)
class _WaitingRequestCard extends ConsumerWidget {
  final MatchRequest request;

  const _WaitingRequestCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinLabel = request.pinName ?? request.locationName ?? '핀 미지정';
    final sportLabel = sports_config.sportLabel(request.sportType);
    final timeLabel = request.timeSlotDisplayName;
    final dateLabel = request.desiredDate ?? '날짜 미정';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          // 상단 — 상대 찾는 중 + 취소
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade600.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: LoadingAnimationWidget.beat(
                      color: Colors.amber.shade600,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '상대를 찾고 있어요',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.amber.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '조건에 맞는 상대가 나타나면 알려드릴게요',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final confirmed = await _showConfirmSheet(
                      context: context,
                      icon: Icons.cancel_outlined,
                      iconColor: AppTheme.errorColor,
                      title: '매칭 요청 취소',
                      subtitle: '대기 중인 매칭 요청을 취소하시겠습니까?',
                      confirmLabel: '취소하기',
                    );
                    if (confirmed != true) return;
                    try {
                      await ref.read(matchRequestProvider.notifier).cancelRequest(request.id);
                      if (context.mounted) AppToast.success('매칭 요청이 취소되었습니다.');
                    } catch (e) {
                      if (context.mounted) AppToast.error(extractErrorMessage(e, '매칭 취소에 실패했습니다.'));
                    }
                  },
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppTheme.textSecondary,
                  tooltip: '취소',
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 구분선
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 1,
            color: const Color(0xFF2A2A2A),
          ),

          const SizedBox(height: 14),

          // 하단 — 정보 칩들
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Column(
              children: [
                // 1줄: 핀 + 종목 + 랭크/친선
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      pinLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sportLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: request.isCasual
                            ? Colors.orange.withOpacity(0.12)
                            : Colors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        request.isCasual ? '친선' : '랭크',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: request.isCasual
                              ? Colors.orange
                              : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 2줄: 날짜/시간 + 성별
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$dateLabel · $timeLabel',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.people_outline_rounded,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      request.genderPreference == 'SAME' ? '같은 성별만' : '성별 상관없음',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// PENDING_ACCEPT 매칭 전체화면 뷰 (최대 2개 카드)
class _PendingMatchFullView extends StatelessWidget {
  final List<Match> matches;

  const _PendingMatchFullView({required this.matches});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < matches.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                i == 0 ? 8 : 6,
                16,
                i == matches.length - 1 ? 16 : 6,
              ),
              child: _PendingMatchCard(
                key: ValueKey(matches[i].id),
                match: matches[i],
              ),
            ),
          ),
      ],
    );
  }
}

/// 개별 PENDING_ACCEPT 매칭 카드 — 타이머 + 수락/거절 인라인
class _PendingMatchCard extends ConsumerStatefulWidget {
  final Match match;

  const _PendingMatchCard({super.key, required this.match});

  @override
  ConsumerState<_PendingMatchCard> createState() => _PendingMatchCardState();
}

class _PendingMatchCardState extends ConsumerState<_PendingMatchCard> {
  Timer? _countdownTimer;
  Duration _remaining = const Duration(minutes: 10);
  bool _hasAccepted = false;
  bool _timerStarted = false;

  static const _totalDuration = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCountdown();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    if (_timerStarted) return;
    _timerStarted = true;

    DateTime? expiresAt;
    if (widget.match.acceptances != null &&
        widget.match.acceptances!.isNotEmpty) {
      final myId = ref.read(currentUserProvider)?.id;
      final myAcceptance = widget.match.acceptances!
          .where((a) => a.userId == myId)
          .firstOrNull;
      expiresAt =
          myAcceptance?.expiresAt ?? widget.match.acceptances!.first.expiresAt;
    }
    // fallback: 서버 expiresAt이 없으면 매칭 생성 시각 + 10분 (로컬 타이머 생성 방지)
    if (expiresAt == null) {
      expiresAt = widget.match.createdAt.add(_totalDuration);
      debugPrint('[Timer] expiresAt not found from server, using fallback: $expiresAt');
    }

    _updateRemaining(expiresAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining(expiresAt!);
    });
  }

  void _updateRemaining(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      _countdownTimer?.cancel();
      if (mounted) {
        setState(() => _remaining = Duration.zero);
        _showSnack('매칭 시간이 초과되었습니다.');
        // 로컬 캐시 강제 만료 + 서버에서 최신 데이터 재조회
        ref.read(matchingRepositoryProvider).clearLocalCache();
        ref.invalidate(matchListProvider(null));
      }
    } else {
      if (mounted) setState(() => _remaining = remaining);
    }
  }

  double get _progressRatio {
    final total = _totalDuration.inSeconds;
    final remaining = _remaining.inSeconds;
    if (total == 0) return 0;
    return (remaining / total).clamp(0.0, 1.0);
  }

  String get _timerText {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color get _timerColor {
    if (_remaining.inMinutes >= 5) return AppTheme.primaryColor;
    if (_remaining.inMinutes >= 2) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  Future<void> _onAccept() async {
    final notifier =
        ref.read(matchAcceptProvider(widget.match.id).notifier);
    final success = await notifier.acceptMatch();
    if (!mounted) return;
    if (success) {
      final acceptState = ref.read(matchAcceptProvider(widget.match.id));
      if (acceptState.acceptStatus == 'MATCHED') {
        // 양측 수락 완료 → chatRoomId가 있으면 채팅방, 없으면 매칭 목록
        ref.invalidate(matchListProvider(null));
        final chatRoomId = acceptState.chatRoomId;
        if (chatRoomId != null && chatRoomId.isNotEmpty && mounted) {
          context.push('/chats/$chatRoomId');
        } else if (mounted) {
          context.go(AppRoutes.matchList);
        }
      } else {
        // 상대 대기 중
        setState(() => _hasAccepted = true);
        notifier.startPolling();
      }
    } else {
      final error =
          ref.read(matchAcceptProvider(widget.match.id)).error ?? '';
      // 404 등 서버에서 매칭을 찾을 수 없으면 로컬 캐시 정리 후 잠금 해제
      ref.read(matchingRepositoryProvider).clearLocalCache();
      ref.invalidate(matchListProvider(null));
      _showSnack(error.contains('찾을 수 없') ? '만료된 매칭입니다.' : '오류: $error');
    }
  }

  Future<void> _onReject() async {
    final confirmed = await _showConfirmSheet(
      context: context,
      icon: Icons.thumb_down_outlined,
      iconColor: AppTheme.errorColor,
      title: '매칭 거절',
      subtitle: '거절하면 -15점 패널티가 적용됩니다.\n정말 거절하시겠습니까?',
      confirmLabel: '거절하기',
    );
    if (confirmed != true || !mounted) return;

    final notifier =
        ref.read(matchAcceptProvider(widget.match.id).notifier);
    final success = await notifier.rejectMatch();
    if (!mounted) return;

    if (success) {
      _showSnack('매칭이 거절되었습니다. (-15점)');
      ref.read(matchingRepositoryProvider).clearLocalCache();
      ref.invalidate(matchListProvider(null));
    } else {
      final error =
          ref.read(matchAcceptProvider(widget.match.id)).error ?? '';
      // 404 등 → 로컬 캐시 정리 후 잠금 해제
      ref.read(matchingRepositoryProvider).clearLocalCache();
      ref.invalidate(matchListProvider(null));
      _showSnack(error.contains('찾을 수 없') ? '만료된 매칭입니다.' : (error.isNotEmpty ? error : '거절 처리 중 오류가 발생했습니다.'));
    }
  }

  void _showSnack(String message) {
    AppToast.info(message);
  }

  @override
  Widget build(BuildContext context) {
    final acceptState = ref.watch(matchAcceptProvider(widget.match.id));

    // CHAT 전환 감지 → 채팅 화면으로 이동
    ref.listen<MatchAcceptState>(
      matchAcceptProvider(widget.match.id),
      (prev, next) {
        if (prev?.updatedMatch?.status != 'CHAT' &&
            next.updatedMatch?.status == 'CHAT' &&
            mounted) {
          final chatRoomId = next.updatedMatch!.chatRoomId;
          if (chatRoomId.isNotEmpty) {
            context.push('/chats/$chatRoomId');
          } else {
            ref.invalidate(matchListProvider(null));
          }
        }
      },
    );

    final opponent = widget.match.opponent;
    final encounterText = widget.match.encounterCount > 0
        ? '${widget.match.encounterCount}번째 만남'
        : '처음 만나는 상대입니다';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── 상대 프로필 ───
            Row(
              children: [
                UserAvatar(
                  imageUrl: opponent.profileImageUrl,
                  size: 56,
                  nickname: opponent.nickname,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opponent.nickname,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 점수 + 경기수
                      Row(
                        children: [
                          Text(
                            opponent.isPlacement ? '배치' : '${opponent.displayScore ?? opponent.currentScore ?? 1000}점',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          if (opponent.gamesPlayed > 0) ...[
                            const Text(' · ', style: TextStyle(color: AppTheme.textDisabled)),
                            Text(
                              '${opponent.gamesPlayed}경기',
                              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 랭크/친선 칩
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: widget.match.isCasual
                        ? Colors.orange.withOpacity(0.15)
                        : Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.match.isCasual ? '친선' : '랭크',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: widget.match.isCasual ? Colors.orange : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ─── 만남 횟수 ───
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.match.encounterCount > 0 ? Icons.repeat_rounded : Icons.waving_hand_rounded,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    encounterText,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── 매칭 정보 (핀 + 종목 + 시간) ───
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        widget.match.pinName ?? '핀 정보 없음',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.match.sportTypeDisplayName,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                  if (widget.match.scheduledDate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.match.scheduledDate}${widget.match.scheduledTime != null ? ' · ${widget.match.scheduledTime}' : ''}',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ─── 타이머 ───
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 16, color: _timerColor),
                const SizedBox(width: 6),
                Text(
                  _timerText,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _timerColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progressRatio,
                minHeight: 5,
                backgroundColor: const Color(0xFF2A2A2A),
                valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
              ),
            ),

            const Spacer(),

            // ─── 수락 후 대기 or 수락/거절 버튼 ───
            if (_hasAccepted)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LoadingAnimationWidget.beat(color: AppTheme.primaryColor, size: 16),
                    const SizedBox(width: 10),
                    const Text(
                      '상대의 응답을 기다리고 있습니다...',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: acceptState.isLoading ? null : _onReject,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('거절 (-15점)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: acceptState.isLoading ? null : _onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: acceptState.isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('수락', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 매칭 규칙 안내 배너 (매칭 잡고 있거나 진행중일 때만 표시)
class _MatchRuleInfoBanner extends ConsumerWidget {
  const _MatchRuleInfoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchListProvider(null)).valueOrNull ?? [];
    final requests = ref.watch(matchRequestProvider).valueOrNull;
    final hasWaiting = requests?.sent.any((r) => r.isWaiting) ?? false;
    final hasActive = matches.any((m) => m.isChat || m.isConfirmed || m.isPendingAccept);

    if (!hasWaiting && !hasActive) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4CAF50).withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '일자 별로 진행중인 매칭이 있으면 추가 매칭은 불가합니다.\n'
              '오늘 경기가 끝나면 새 매칭을 잡을 수 있고, 내일 경기도 1개 예약할 수 있습니다.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF81C784),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchListTile extends ConsumerStatefulWidget {
  final Match match;
  final VoidCallback? onTap;

  const _MatchListTile({required this.match, this.onTap});

  @override
  ConsumerState<_MatchListTile> createState() => _MatchListTileState();
}

class _MatchListTileState extends ConsumerState<_MatchListTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lightController;
  late final Animation<double> _lightX;
  late final Animation<double> _lightY;
  late final double _seed;

  @override
  void initState() {
    super.initState();
    final hash = widget.match.id.hashCode;
    _seed = ((hash & 0xFFFF) % 1000) / 1000.0;
    final seed2 = (((hash >> 16) & 0xFFFF) % 1000) / 1000.0;
    final duration = Duration(milliseconds: 4000 + ((_seed * 3000).toInt()));
    _lightController = AnimationController(vsync: this, duration: duration)
      ..repeat(reverse: true);
    // 시작점/끝점 모두 seed 기반 랜덤 → 카드마다 완전히 다른 궤적
    final startX = -0.8 + seed2 * 1.6; // -0.8 ~ 0.8
    final startY = -0.6 + _seed * 1.2;  // -0.6 ~ 0.6
    final endX = -0.8 + _seed * 1.6;
    final endY = -0.6 + seed2 * 1.2;
    _lightX = Tween<double>(begin: startX, end: endX)
        .animate(CurvedAnimation(parent: _lightController, curve: Curves.easeInOut));
    _lightY = Tween<double>(begin: startY, end: endY)
        .animate(CurvedAnimation(parent: _lightController, curve: const Interval(0.15, 0.85, curve: Curves.easeInOutSine)));
  }

  @override
  void dispose() {
    _lightController.dispose();
    super.dispose();
  }

  Match get match => widget.match;
  VoidCallback? get onTap => widget.onTap;

  /// scheduledDate(YYYY-MM-DD)를 "오늘" / "내일" / 날짜 문자열로 변환
  String _dateLabel(String? scheduledDate) {
    if (scheduledDate == null) return '';
    try {
      final date = DateTime.parse(scheduledDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(date.year, date.month, date.day);
      final diff = target.difference(today).inDays;
      if (diff == 0) return '오늘';
      if (diff == 1) return '내일';
      return scheduledDate;
    } catch (_) {
      return scheduledDate;
    }
  }

  /// 좌측 강조 색상
  Color _statusAccentColor() {
    if (match.isCompleted && match.gameResult != null) {
      switch (match.gameResult) {
        case 'WIN':
          return const Color(0xFF22C55E); // 선명한 초록
        case 'LOSS':
          return const Color(0xFFEF4444); // 선명한 빨강
        case 'DRAW':
          return const Color(0xFF9CA3AF);
      }
    }
    if (match.isCancelled) return const Color(0xFF9CA3AF);
    switch (match.status) {
      case 'PENDING_ACCEPT':
        return Colors.amber;
      case 'CHAT':
        return AppTheme.primaryColor;
      case 'CONFIRMED':
        return Colors.blue;
      default:
        return const Color(0xFFD1D5DB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _statusAccentColor();
    final unreadCount = (match.chatRoomId.isNotEmpty)
        ? ref.watch(roomUnreadCountProvider(match.chatRoomId))
        : 0;

    final tierColor = AppTheme.tierColor(match.opponent.tier);

    return Stack(
      children: [
      AnimatedBuilder(
        animation: _lightController,
        builder: (context, child) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFF1E1E1E), accentColor, 0.22),
            border: Border(
              left: BorderSide(color: accentColor, width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(_lightX.value, _lightY.value),
              radius: 1.5,
              colors: [
                accentColor.withValues(alpha: 0.25),
                accentColor.withValues(alpha: 0.05),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 큰 아바타 + 티어 테두리
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: tierColor.withValues(alpha: 0.5), width: 2),
                  ),
                  child: UserAvatar(
                    imageUrl: match.opponent.profileImageUrl,
                    size: 56,
                    nickname: match.opponent.nickname,
                  ),
                ),
                const SizedBox(width: 14),

                // 정보 영역
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1행: 닉네임 + 결과
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              match.opponent.nickname,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (match.isCasual)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('친선', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange.shade300)),
                              ),
                            ),
                          if (match.isCompleted && match.gameResult != null)
                            _GameResultChip(gameResult: match.gameResult!, scoreChange: match.myScoreChange, isCasual: match.isCasual)
                          else
                            _StatusChip(status: match.status),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // 진행중 상태
                      if (match.isChat || match.isConfirmed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _ActiveStatusRow(match: match),
                        ),

                      // 2행: 티어
                      if (!match.opponent.isPlacement)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: tierColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              match.opponent.tier,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tierColor),
                            ),
                          ),
                        ),

                      // 3행: 종목 / 날짜 / 핀
                      Row(
                        children: [
                          Icon(sports_config.sportIcon(match.sportType), size: 12, color: const Color(0xFFB0B7C3)),
                          const SizedBox(width: 3),
                          Text(match.sportTypeDisplayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB0B7C3))),
                          if (match.desiredDate != null) ...[
                            const Text(' / ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B7580))),
                            Text(
                              '${_dateLabel(match.desiredDate)}${match.desiredTimeSlot != null && match.desiredTimeSlot != 'ANY' ? ' ${match.desiredTimeSlotDisplayName}' : ''}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8B95A5)),
                            ),
                          ],
                          if (match.pinName != null) ...[
                            const Text(' / ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B7580))),
                            Flexible(
                              child: Text(match.pinName!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8B95A5)), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ],
                      ),

                      // PENDING_ACCEPT 칩
                      if (match.isPendingAccept) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _InfoChip(
                              icon: match.encounterCount > 0 ? Icons.people_rounded : Icons.person_add_rounded,
                              text: match.encounterCount > 0 ? '${match.encounterCount}번 만남' : '첫 매칭',
                              color: match.encounterCount > 0 ? const Color(0xFF10B981) : null,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
      ),
      // 읽지 않은 메시지 배지
      if (unreadCount > 0)
        Positioned(
          top: 0,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

}

/// PENDING_ACCEPT 카드용 정보 칩
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: c),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: c),
        ),
      ],
    );
  }
}

/// 진행중 탭 전용 상태 인디케이터 행
class _ActiveStatusRow extends StatelessWidget {
  final Match match;

  const _ActiveStatusRow({required this.match});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    String label;

    if (match.isPendingAccept) {
      dotColor = Colors.amber;
      label = '수락 대기중';
    } else if (match.isChat) {
      dotColor = AppTheme.primaryColor;
      label = '매칭 성사 · 경기 전';
    } else {
      // CONFIRMED
      dotColor = Colors.blue;
      label = '경기 확정';
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: dotColor,
          ),
        ),
      ],
    );
  }
}

/// 날짜 배지 — "오늘" / "내일" 강조 표시
class _DateBadge extends StatelessWidget {
  final String label;

  const _DateBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final isToday = label == '오늘';
    final isTomorrow = label == '내일';
    final highlight = isToday || isTomorrow;

    if (!highlight) {
      return Text(
        label,
        style:
            const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isToday
            ? AppTheme.secondaryColor.withOpacity(0.12)
            : Colors.blue.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color:
              isToday ? AppTheme.secondaryColor : Colors.blue.shade700,
        ),
      ),
    );
  }
}

class _GameResultChip extends StatelessWidget {
  final String gameResult;
  final int? scoreChange;
  final bool isCasual;

  const _GameResultChip({
    required this.gameResult,
    this.scoreChange,
    this.isCasual = false,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;

    switch (gameResult) {
      case 'WIN':
        label = '승리';
        color = AppTheme.secondaryColor;
        break;
      case 'LOSS':
        label = '패배';
        color = AppTheme.errorColor;
        break;
      case 'DRAW':
        label = '무승부';
        color = const Color(0xFF9CA3AF);
        break;
      case 'DISPUTED':
        label = '이의제기';
        color = Colors.orange;
        break;
      case 'NO_RESULT':
        label = '미입력';
        color = const Color(0xFF6B7280);
        break;
      default:
        label = '완료';
        color = const Color(0xFF9CA3AF);
    }

    final hasScore = scoreChange != null && scoreChange != 0 && !isCasual;
    final sign = (scoreChange ?? 0) > 0 ? '+' : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (hasScore) ...[
          const SizedBox(width: 4),
          Text(
            '$sign$scoreChange',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: (scoreChange ?? 0) > 0
                  ? AppTheme.secondaryColor
                  : AppTheme.errorColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 'PENDING_ACCEPT':
        color = Colors.amber.shade700;
        label = '상대 응답 대기';
        break;
      case 'CHAT':
        color = AppTheme.primaryColor;
        label = '채팅 중';
        break;
      case 'CONFIRMED':
        color = Colors.blue;
        label = '경기 확정';
        break;
      case 'COMPLETED':
        color = AppTheme.textSecondary;
        label = '완료';
        break;
      case 'CANCELLED':
        color = AppTheme.textDisabled;
        label = '취소';
        break;
      case 'DISPUTED':
        color = AppTheme.errorColor;
        label = '분쟁';
        break;
      default:
        color = AppTheme.textSecondary;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 공통 확인 바텀시트 — 파괴적 액션(빨간 버튼)용
Future<bool?> _showConfirmSheet({
  required BuildContext context,
  required IconData icon,
  required Color iconColor,
  required String title,
  required String subtitle,
  required String confirmLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // 아이콘
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          // 제목
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // 부제목
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          // 버튼 행
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF2A2A2A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '아니오',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

