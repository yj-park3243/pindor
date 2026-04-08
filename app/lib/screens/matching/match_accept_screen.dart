import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../providers/matching_provider.dart';
import '../../providers/auth_provider.dart';

/// 매칭 수락 화면 (PENDING_ACCEPT 상태)
/// - 10분 카운트다운 타이머 (서버의 expiresAt 기준)
/// - 수락 → 상대 응답 대기
/// - 양측 수락 시 채팅 화면으로 자동 이동
/// - 거절 → 토스트 + 목록 이동
/// - PopScope로 뒤로가기 차단 (매칭 잠금)
class MatchAcceptScreen extends ConsumerStatefulWidget {
  final String matchId;

  const MatchAcceptScreen({super.key, required this.matchId});

  @override
  ConsumerState<MatchAcceptScreen> createState() => _MatchAcceptScreenState();
}

class _MatchAcceptScreenState extends ConsumerState<MatchAcceptScreen> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _hasAccepted = false; // 내가 수락 버튼을 눌렀는지
  bool _timerStarted = false;

  // 총 타이머 시간 — 10분 기준 (요구사항)
  static const Duration _totalDuration = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMatchAndStartTimer();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMatchAndStartTimer() async {
    final matchAsync = ref.read(matchDetailProvider(widget.matchId));
    matchAsync.whenData((match) {
      _startCountdown(match);
    });
  }

  void _startCountdown(Match match) {
    if (_timerStarted) return;
    _timerStarted = true;

    // expiresAt이 있는 acceptances에서 만료 시각 가져오기
    // 없으면 현재로부터 10분 후 기본값 사용
    DateTime? expiresAt;
    if (match.acceptances != null && match.acceptances!.isNotEmpty) {
      final myId = ref.read(currentUserProvider)?.id;
      final myAcceptance = match.acceptances!
          .where((a) => a.userId == myId)
          .firstOrNull;
      expiresAt = myAcceptance?.expiresAt ?? match.acceptances!.first.expiresAt;
    }
    expiresAt ??= DateTime.now().add(_totalDuration);

    _countdownTimer?.cancel();
    _updateRemaining(expiresAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining(expiresAt!);
    });
  }

  void _updateRemaining(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      _countdownTimer?.cancel();
      setState(() => _remaining = Duration.zero);
      if (mounted) {
        _showToast('매칭 시간이 초과되었습니다.');
        context.go(AppRoutes.matchList);
      }
    } else {
      setState(() => _remaining = remaining);
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

  Future<void> _onAccept() async {
    final notifier = ref.read(matchAcceptProvider(widget.matchId).notifier);
    final match = await notifier.acceptMatch();
    if (!mounted) return;

    if (match != null) {
      setState(() => _hasAccepted = true);
      // 폴링 시작 — 상대가 수락하면 채팅 화면으로 이동
      notifier.startPolling();
    } else {
      final error = ref.read(matchAcceptProvider(widget.matchId)).error ?? '';
      _showToast('오류: $error');
    }
  }

  Future<void> _onReject() async {
    // 거절 재확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('매칭 거절'),
        content: const Text('거절하면 -15점 패널티가 적용됩니다.\n정말 거절하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('거절하기'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final notifier = ref.read(matchAcceptProvider(widget.matchId).notifier);
    final success = await notifier.rejectMatch();
    if (!mounted) return;

    if (success) {
      _showToast('매칭이 거절되었습니다. (-15점)');
      context.go(AppRoutes.matchList);
    } else {
      final error = ref.read(matchAcceptProvider(widget.matchId)).error ?? '';
      // 쿨다운 에러 메시지 처리 (서버에서 내려오는 형태 그대로 표시)
      _showToast(error.isNotEmpty ? error : '거절 처리 중 오류가 발생했습니다.');
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acceptState = ref.watch(matchAcceptProvider(widget.matchId));
    final matchAsync = ref.watch(matchDetailProvider(widget.matchId));

    // 수락 후 상태 변경 감지 (CHAT으로 전환 시 채팅 이동)
    ref.listen<MatchAcceptState>(
      matchAcceptProvider(widget.matchId),
      (prev, next) {
        if (next.updatedMatch != null &&
            next.updatedMatch!.status == 'CHAT' &&
            mounted) {
          context.go(
            AppRoutes.chatList + '/${next.updatedMatch!.chatRoomId}',
          );
        }
      },
    );

    return PopScope(
      canPop: false, // 뒤로가기 차단 — 매칭 화면 잠금
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('매칭 성사!'),
          backgroundColor: const Color(0xFFF8F9FA),
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: matchAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                const SizedBox(height: 12),
                Text('매칭 정보를 불러올 수 없습니다.\n$e',
                    textAlign: TextAlign.center),
              ],
            ),
          ),
          data: (match) {
            // 최초 로드 시 타이머 시작
            if (!_timerStarted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _startCountdown(match);
              });
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // ─── 매칭 성사 헤더 ───
                    _MatchSuccessHeader(),

                    const SizedBox(height: 20),

                    // ─── 상대 프로필 카드 (닉네임/랭킹/종목 표시) ───
                    _OpponentCard(opponent: match.opponent),

                    const SizedBox(height: 24),

                    // ─── 타이머 ───
                    _TimerSection(
                      timerText: _timerText,
                      progressRatio: _progressRatio,
                      remaining: _remaining,
                    ),

                    const SizedBox(height: 32),

                    // ─── 수락 대기 메시지 or 버튼 ───
                    if (_hasAccepted)
                      const _WaitingForOpponent()
                    else
                      _AcceptRejectButtons(
                        isLoading: acceptState.isLoading,
                        onAccept: _onAccept,
                        onReject: _onReject,
                      ),

                    const SizedBox(height: 20),

                    // ─── 거절 주의 안내 ───
                    if (!_hasAccepted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.warningColor.withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: AppTheme.warningColor,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '거절 시 -15점 패널티가 적용됩니다.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── 매칭 성사 헤더 ───
class _MatchSuccessHeader extends StatelessWidget {
  const _MatchSuccessHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.sports_rounded,
            size: 32,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '매칭 상대를 찾았습니다!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '10분 내로 수락 여부를 결정해주세요.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── 상대 프로필 카드 (닉네임 / 랭킹 / 종목) ───
class _OpponentCard extends StatelessWidget {
  final MatchOpponent opponent;

  const _OpponentCard({required this.opponent});

  /// 배치 중 여부에 따라 랭킹 텍스트 반환
  String get _rankText {
    if (opponent.isPlacement) return '배치 중';
    // currentScore가 없으면 티어만 표시
    return opponent.tier;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── 상대방 정보 라벨 ───
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '상대방 정보',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 프로필 아이콘
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4), width: 2.5),
            ),
            child: opponent.profileImageUrl != null
                ? ClipOval(
                    child: Image.network(
                      opponent.profileImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
          ),
          const SizedBox(height: 16),

          // 닉네임
          Text(
            opponent.nickname,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),

          // 랭킹 / 종목 정보
          _InfoRow(
            items: [
              _InfoItem(
                label: '랭킹',
                value: _rankText,
                valueColor: opponent.isPlacement
                    ? AppTheme.textSecondary
                    : AppTheme.primaryColor,
              ),
              _InfoItem(
                label: '종목',
                value: _sportDisplayName(opponent.sportType),
              ),
              _InfoItem(
                label: '전적',
                value: '${opponent.wins}승 ${opponent.losses}패',
              ),
            ],
          ),

          // 매칭 문구 (있을 때만 표시)
          if (opponent.matchMessage != null && opponent.matchMessage!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      opponent.matchMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sportDisplayName(String sportType) {
    switch (sportType) {
      case 'GOLF': return '골프';
      case 'BILLIARDS': return '당구';
      case 'TENNIS': return '테니스';
      case 'TABLE_TENNIS': return '탁구';
      default: return sportType;
    }
  }
}

class _InfoItem {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoItem({
    required this.label,
    required this.value,
    this.valueColor,
  });
}

class _InfoRow extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.expand((item) sync* {
        yield _InfoCell(item: item);
        if (item != items.last) {
          yield Container(
            width: 1,
            height: 30,
            color: const Color(0xFFE5E7EB),
          );
        }
      }).toList(),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final _InfoItem item;

  const _InfoCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          item.value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: item.valueColor ?? AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── 타이머 섹션 ───
class _TimerSection extends StatelessWidget {
  final String timerText;
  final double progressRatio;
  final Duration remaining;

  const _TimerSection({
    required this.timerText,
    required this.progressRatio,
    required this.remaining,
  });

  Color get _timerColor {
    if (remaining.inMinutes >= 10) return AppTheme.primaryColor;
    if (remaining.inMinutes >= 5) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 18, color: _timerColor),
            const SizedBox(width: 6),
            Text(
              '남은 시간: ',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              timerText,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _timerColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progressRatio,
            minHeight: 8,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
          ),
        ),
      ],
    );
  }
}

// ─── 수락/거절 버튼 ───
class _AcceptRejectButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _AcceptRejectButtons({
    required this.isLoading,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 거절 버튼 — 빨간색, -15점 패널티 표시
        Expanded(
          child: ElevatedButton(
            onPressed: isLoading ? null : onReject,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '거절',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '(-15점)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 수락 버튼 — 파란색/초록색
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: isLoading ? null : onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '수락',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── 수락 후 대기 화면 ───
class _WaitingForOpponent extends StatelessWidget {
  const _WaitingForOpponent();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '상대의 응답을 기다리고 있습니다...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '상대방이 수락하면 채팅이 시작됩니다.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
