import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../models/match_request.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../providers/matching_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/matching_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/user_avatar.dart';
import '../../widgets/common/score_display.dart';
import '../../providers/chat_provider.dart';


/// 매칭 목록 화면 (PRD SCREEN-020)
/// 진행중/완료/취소 SegmentedButton 탭
/// PENDING_ACCEPT 상태 매칭이 있으면 전체화면 잠금 모드로 전환
class MatchListScreen extends ConsumerStatefulWidget {
  final int initialTab;

  const MatchListScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends ConsumerState<MatchListScreen> {
  late int _selectedIndex;
  Timer? _autoRefreshTimer;
  bool _redirectedToAccept = false; // 무한 루프 방지 가드

  static const _tabs = ['진행중', '완료', '취소'];
  static const List<String?> _statuses = [null, 'COMPLETED', 'CANCELLED'];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, _tabs.length - 1);
    // 화면 진입 시 매칭 목록 + 요청 목록 새로고침
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(matchListProvider(null));
      ref.invalidate(matchRequestProvider);
    });
    // WAITING 요청이 있으면 30초마다 자동 갱신 (소켓 알림 누락 대비)
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        ref.invalidate(matchListProvider(null));
        ref.invalidate(matchRequestProvider);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allMatchesAsync = ref.watch(matchListProvider(null));
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

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('매칭'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        actions: const [],
      ),
      body: Column(
        children: [
          // ─── 노쇼 제한 배너 (TODO: API에서 matchBanUntil 제공 시 연동) ───
          // ignore: dead_code
          if (false)
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

          // 커스텀 탭 바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEFF1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final selected = _selectedIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withOpacity(0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _tabs[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? Colors.white : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
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
        // 진행중 탭: CHAT, CONFIRMED + 내가 수락한 PENDING_ACCEPT
        final filteredList = isActiveFilter
            ? matchList.where((m) {
                if (m.isChat || m.isConfirmed) return true;
                // 내가 수락 완료한 PENDING_ACCEPT (상대 응답 대기 중) 도 표시
                if (m.isPendingAccept && m.acceptances?.any((a) => a.accepted == true) == true) return true;
                return false;
              }).toList()
            : matchList;

        final requestsAsync = ref.watch(matchRequestProvider);
        final waitingRequests = isActiveFilter
            ? (requestsAsync.valueOrNull?.sent.where((r) => r.isWaiting).toList() ?? [])
            : <MatchRequest>[];
        final waitingCount = waitingRequests.length;

        if (filteredList.isEmpty && !isActiveFilter) {
          return EmptyState(
            icon: Icons.sports_score_rounded,
            title: status == 'COMPLETED'
                ? '완료된 매칭이 없습니다'
                : '취소된 매칭이 없습니다',
          );
        }

        if (filteredList.isEmpty && isActiveFilter) {
          // matchRequestProvider 아직 로딩 중이면 로딩 표시
          if (requestsAsync.isLoading) {
            return const FullScreenLoading();
          }

          if (waitingCount > 0) {
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                ...waitingRequests.map((req) => _WaitingRequestCard(request: req)),
                _MatchSlotBanner(activeCount: waitingCount),
              ],
            );
          }

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

        // 매칭 목록: 진행중 매치(날짜순) → 대기중 요청 → 슬롯 배너(맨 아래)
        final totalActiveCount = filteredList.length + waitingCount;
        // 진행중 매치를 날짜순 정렬
        if (isActiveFilter && filteredList.length > 1) {
          filteredList.sort((a, b) {
            final aDate = a.scheduledDate ?? a.createdAt.toIso8601String();
            final bDate = b.scheduledDate ?? b.createdAt.toIso8601String();
            return aDate.compareTo(bDate);
          });
        }
        // 순서: [0..N-1] 매치 카드 → [N..N+W-1] 대기 카드 → [마지막] 배너
        final bannerCount = isActiveFilter ? 1 : 0;
        final totalItems = filteredList.length + (isActiveFilter ? waitingCount : 0) + bannerCount;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(matchListProvider(status));
            ref.invalidate(matchRequestProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: totalItems,
            itemBuilder: (context, index) {
              if (isActiveFilter) {
                // 매치 카드
                if (index < filteredList.length) {
                  return _MatchListTile(
                    match: filteredList[index],
                    onTap: () => context.go(
                        '${AppRoutes.matchList}/${filteredList[index].id}'),
                  );
                }
                // 대기 카드
                final waitingIndex = index - filteredList.length;
                if (waitingIndex < waitingRequests.length) {
                  return _WaitingRequestCard(request: waitingRequests[waitingIndex]);
                }
                // 슬롯 배너 (맨 아래)
                return _MatchSlotBanner(activeCount: totalActiveCount);
              }
              return _MatchListTile(
                match: filteredList[index],
                onTap: () => context
                    .go('${AppRoutes.matchList}/${filteredList[index].id}'),
              );
            },
          ),
        );
      },
    );
  }
}

/// 매칭 대기 중 배너 — 2줄 간단 표시
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

  String _sportLabel(String sportType) {
    switch (sportType) {
      case 'GOLF':
        return '골프';
      case 'BILLIARDS':
        return '당구';
      case 'TENNIS':
        return '테니스';
      case 'TABLE_TENNIS':
        return '탁구';
      default:
        return sportType;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinLabel = request.pinName ?? request.locationName ?? '핀 미지정';
    final sportLabel = _sportLabel(request.sportType);
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
                      if (context.mounted) AppToast.error('취소 실패: $e');
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
          context.go('${AppRoutes.chatList}/$chatRoomId');
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
            context.go('${AppRoutes.chatList}/$chatRoomId');
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

/// 매칭 슬롯 카운터 배너 (진행중 탭 최상단)
class _MatchSlotBanner extends StatelessWidget {
  final int activeCount;

  const _MatchSlotBanner({required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final remaining = 2 - activeCount;
    if (remaining <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sports_score_rounded,
            size: 15,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            '매칭 가능: $remaining개 남음 (오늘/내일)',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchListTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = _statusAccentColor();
    final unreadCount = (match.chatRoomId.isNotEmpty)
        ? ref.watch(roomUnreadCountProvider(match.chatRoomId))
        : 0;

    return Stack(
      children: [
      Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: match.opponent.profileImageUrl,
                size: 60,
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
                            score: match.opponent.displayScore ??
                                match.opponent.currentScore ??
                                0,
                            isPlacement: true,
                            placementGamesRemaining:
                                match.opponent.placementGamesRemaining,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          )
                        else if ((match.opponent.displayScore ??
                                match.opponent.currentScore) !=
                            null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryColor.withOpacity(0.18),
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
                              border: Border.all(
                                  color: Colors.orange.shade200),
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

                    // 진행중 상태 인디케이터 (CHAT / CONFIRMED)
                    if (match.isChat || match.isConfirmed)
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
                            style:
                                TextStyle(color: AppTheme.textSecondary),
                          ),
                          // 날짜 배지 ("오늘" / "내일" / 날짜)
                          _DateBadge(
                              label: _dateLabel(match.scheduledDate)),
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

                    // PENDING_ACCEPT — 핀 위치 + 희망 시간 + 만남 횟수
                    if (match.isPendingAccept) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (match.pinName != null)
                            _InfoChip(
                              icon: Icons.location_on_rounded,
                              text: match.pinName!,
                            ),
                          if (match.desiredDate != null)
                            _InfoChip(
                              icon: Icons.calendar_today_rounded,
                              text: '${_dateLabel(match.desiredDate)}${match.desiredTimeSlot != null && match.desiredTimeSlot != 'ANY' ? ' ${match.desiredTimeSlotDisplayName}' : ''}',
                            ),
                          _InfoChip(
                            icon: match.encounterCount > 0
                                ? Icons.people_rounded
                                : Icons.person_add_rounded,
                            text: match.encounterCount > 0
                                ? '${match.encounterCount}번 만남'
                                : '첫 매칭',
                            color: match.encounterCount > 0
                                ? const Color(0xFF10B981)
                                : null,
                          ),
                        ],
                      ),
                    ],
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
