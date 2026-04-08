import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../providers/matching_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/user_avatar.dart';
import '../../widgets/common/score_display.dart';


/// 매칭 목록 화면 (PRD SCREEN-020)
/// 진행중/완료/취소 SegmentedButton 탭
class MatchListScreen extends ConsumerStatefulWidget {
  const MatchListScreen({super.key});

  @override
  ConsumerState<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends ConsumerState<MatchListScreen> {
  int _selectedIndex = 0;

  static const _tabs = ['진행중', '완료', '취소'];
  // 전체 조회(null) 후 로컬에서 CHAT/CONFIRMED 필터링
  static const List<String?> _statuses = [null, 'COMPLETED', 'CANCELLED'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('매칭'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => context.go(AppRoutes.createMatch),
            tooltip: '매칭 요청 생성',
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── 노쇼 제한 배너 (TODO: API에서 matchBanUntil 제공 시 연동) ───
          // ignore: dead_code
          if (false) // TODO: ref.watch(userNotifierProvider).valueOrNull?.matchBanUntil != null
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.block, color: Colors.red),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '노쇼로 인해 매칭이 제한되었습니다.\n제한 해제 후 매칭 가능합니다.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // SegmentedButton 스타일 탭 바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: AdaptiveSegmentedControl(
              labels: _tabs,
              selectedIndex: _selectedIndex,
              onValueChanged: (index) => setState(() => _selectedIndex = index),
            ),
          ),

          // 탭 콘텐츠
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _MatchTabView(
                key: ValueKey(_selectedIndex),
                status: _statuses[_selectedIndex],
                isActiveFilter: _selectedIndex == 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchTabView extends ConsumerWidget {
  final String? status;
  /// true이면 전체 조회 후 CHAT/CONFIRMED만 로컬 필터링
  final bool isActiveFilter;

  const _MatchTabView({
    super.key,
    required this.status,
    this.isActiveFilter = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchListProvider(status));

    return matches.when(
      loading: () => const FullScreenLoading(),
      error: (e, _) => ErrorView(
        message: '매칭 목록을 불러올 수 없습니다.',
        onRetry: () => ref.invalidate(matchListProvider(status)),
      ),
      data: (matchList) {
        // 진행중 탭: PENDING_ACCEPT, CHAT, CONFIRMED 포함
        final filteredList = isActiveFilter
            ? matchList
                .where((m) => m.isPendingAccept || m.isChat || m.isConfirmed)
                .toList()
            : matchList;

        if (filteredList.isEmpty && !isActiveFilter) {
          return EmptyState(
            icon: Icons.sports_score_rounded,
            title: status == 'COMPLETED'
                ? '완료된 매칭이 없습니다'
                : '취소된 매칭이 없습니다',
          );
        }

        if (filteredList.isEmpty && isActiveFilter) {
          // 진행 중 매칭 없을 때 — 매칭 요청 대기 상태도 확인
          final requestsAsync = ref.watch(matchRequestProvider);
          final waitingCount = requestsAsync.valueOrNull?.sent.length ?? 0;

          if (waitingCount > 0) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 48, color: AppTheme.primaryColor),
                  const SizedBox(height: 12),
                  Text(
                    '매칭 대기 중 ($waitingCount건)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '상대를 찾고 있습니다...',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.matchRequests),
                    child: const Text('매칭 요청 목록 보기'),
                  ),
                ],
              ),
            );
          }

          return GestureDetector(
            onTap: () => context.go(AppRoutes.map),
            child: const EmptyState(
              icon: Icons.sports_score_rounded,
              title: '진행 중인 매칭이 없습니다',
              subtitle: '탭하여 핀에서 대결을 신청하세요!',
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(matchListProvider(status));
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: filteredList.length + (isActiveFilter ? 1 : 0),
            itemBuilder: (context, index) {
              // 진행중 탭 최상단: 매칭 슬롯 카운터
              if (isActiveFilter && index == 0) {
                return _MatchSlotBanner(activeCount: filteredList.length);
              }
              final matchIndex = isActiveFilter ? index - 1 : index;
              return _MatchListTile(
                match: filteredList[matchIndex],
                onTap: () => context
                    .go('${AppRoutes.matchList}/${filteredList[matchIndex].id}'),
              );
            },
          ),
        );
      },
    );
  }
}

/// 매칭 슬롯 카운터 배너 (진행중 탭 최상단)
class _MatchSlotBanner extends StatelessWidget {
  final int activeCount;

  const _MatchSlotBanner({required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final remaining = 2 - activeCount;
    final isFull = remaining <= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isFull
            ? Colors.orange.shade50
            : AppTheme.primaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFull
              ? Colors.orange.shade200
              : AppTheme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFull ? Icons.lock_outline : Icons.sports_score_rounded,
            size: 15,
            color: isFull ? Colors.orange.shade700 : AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            isFull
                ? '매칭이 가득 찼습니다 (오늘/내일 2개 진행 중)'
                : '매칭 가능: $remaining개 남음 (오늘/내일)',
            style: TextStyle(
              fontSize: 12,
              color: isFull ? Colors.orange.shade700 : AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchListTile extends StatelessWidget {
  final Match match;
  final VoidCallback? onTap;

  const _MatchListTile({required this.match, this.onTap});

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

  /// 진행중 상태에서 좌측 강조 색상
  Color _statusAccentColor() {
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: accentColor, width: 3.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: match.opponent.profileImageUrl,
                size: 50,
                nickname: match.opponent.nickname,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상단 행: 닉네임 + 점수 + 우측 배지
                    Row(
                      children: [
                        Text(
                          match.opponent.nickname,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 상대방 배치 게임 또는 점수 뱃지
                        if (match.opponent.isPlacement)
                          ScoreText(
                            score: match.opponent.displayScore ?? match.opponent.currentScore ?? 0,
                            isPlacement: true,
                            placementGamesRemaining: match.opponent.placementGamesRemaining,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          )
                        else if ((match.opponent.displayScore ?? match.opponent.currentScore) != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${match.opponent.displayScore ?? match.opponent.currentScore}점',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // 친선 게임 배지
                        if (match.isCasual) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Text(
                              '친선',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        _StatusChip(status: match.status),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // 진행중 상태 인디케이터 (PENDING_ACCEPT / CHAT / CONFIRMED)
                    if (match.isPendingAccept || match.isChat || match.isConfirmed)
                      _ActiveStatusRow(match: match),

                    const SizedBox(height: 4),

                    // 종목 + 날짜
                    Row(
                      children: [
                        Icon(
                          _getSportIcon(match.sportTypeDisplayName),
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          match.sportTypeDisplayName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (match.scheduledDate != null) ...[
                          const Text(
                            ' · ',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          // 날짜 배지 ("오늘" / "내일" / 날짜)
                          _DateBadge(label: _dateLabel(match.scheduledDate)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (match.venueName != null)
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 12, color: AppTheme.textDisabled),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              match.venueName!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textDisabled,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: AppTheme.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSportIcon(String sport) {
    switch (sport) {
      case '골프':
        return Icons.sports_golf;
      case '테니스':
      case '탁구':
      case '배드민턴':
        return Icons.sports_tennis;
      case '볼링':
        return Icons.sports;
      default:
        return Icons.sports_score;
    }
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
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
          color: isToday ? AppTheme.secondaryColor : Colors.blue.shade700,
        ),
      ),
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
        label = '수락 대기';
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
