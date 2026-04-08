import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../providers/matching_provider.dart';
import '../../repositories/matching_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';

import '../../widgets/common/user_avatar.dart';
import 'opponent_profile_sheet.dart';

/// 노쇼 신고 확인 다이얼로그
void _showNoshowConfirmDialog(
    BuildContext context, WidgetRef ref, String matchId) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('노쇼 신고'),
      content: const Text(
        '상대방이 약속 장소에 나타나지 않았나요?\n\n'
        '노쇼 신고 시:\n'
        '  • 상대방: -30점 + 7일 매칭 제한\n'
        '  • 2회 적발 시 영구 정지\n'
        '  • 나: +15점 보상\n\n'
        '허위 신고 시 제재를 받을 수 있습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await ref.read(matchingRepositoryProvider).reportNoshow(matchId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('노쇼 신고가 접수되었습니다.')),
                );
                context.go('/matches');
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('신고 실패: $e')),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('신고하기', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// 매칭 상세 화면
/// VS 레이아웃 + 매칭 정보 + 액션 버튼
class MatchDetailScreen extends ConsumerWidget {
  final String matchId;

  const MatchDetailScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchAsync = ref.watch(matchDetailProvider(matchId));

    return matchAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: FullScreenLoading(),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('매칭 상세'),
          backgroundColor: const Color(0xFFF8F9FA),
          elevation: 0,
        ),
        body: ErrorView(
          message: '매칭 정보를 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(matchDetailProvider(matchId)),
        ),
      ),
      data: (match) {
        // PENDING_ACCEPT / CHAT / CONFIRMED 상태에서 뒤로가기 차단
        final shouldLock =
            match.isPendingAccept || match.isChat || match.isConfirmed;
        // 노쇼 신고 가능 상태: CHAT 또는 CONFIRMED
        final shouldShowNoshow = match.isChat || match.isConfirmed;

        return PopScope(
          canPop: !shouldLock,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: AppBar(
              title: const Text('매칭 상세'),
              backgroundColor: const Color(0xFFF8F9FA),
              elevation: 0,
              automaticallyImplyLeading: !shouldLock,
              actions: [
                if (shouldShowNoshow)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'noshow') {
                        // _MatchDetailContent의 메서드 접근을 위해 별도 키 사용 대신
                        // GlobalKey를 통하지 않고 직접 dialog를 여기서 표시
                        _showNoshowConfirmDialog(context, ref, matchId);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'noshow',
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('노쇼 신고'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: _MatchDetailContent(match: match, matchId: matchId),
          ),
        );
      },
    );
  }
}

class _MatchDetailContent extends ConsumerStatefulWidget {
  final Match match;
  final String matchId;

  const _MatchDetailContent({required this.match, required this.matchId});

  @override
  ConsumerState<_MatchDetailContent> createState() =>
      _MatchDetailContentState();
}

class _MatchDetailContentState extends ConsumerState<_MatchDetailContent> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    final match = widget.match;

    return SingleChildScrollView(
      child: Column(
        children: [
          // ─── VS 레이아웃 헤더 ───
          _VSHeader(match: match),

          // ─── 친선 게임 배너 ───
          if (match.isCasual)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.orange.shade50,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.handshake_outlined,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      '친선 게임 · 점수에 반영되지 않습니다',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── 상태 배지 ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _StatusBanner(status: match.status),
          ),

          // ─── 경기 정보 카드 ───
          _MatchInfoCard(match: match),

          const SizedBox(height: 20),

          // ─── 액션 버튼들 ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // 채팅하기
                if (match.isChat || match.isConfirmed) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          context.go('/chats/${match.chatRoomId}'),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                      label: const Text('채팅하기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 경기 확정 (채팅 중일 때)
                if (match.isChat) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _showConfirmMatchDialog(context),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 18),
                      label: const Text('경기 확정'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 결과 입력 (확정 후)
                if (match.isConfirmed && match.gameId != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          context.go('/games/${match.gameId}/result'),
                      icon: const Icon(Icons.assignment_rounded, size: 18),
                      label: const Text('결과 입력'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 상대 프로필 보기
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showOpponentProfile(context, match.opponent),
                    icon: const Icon(Icons.person_outline_rounded, size: 18),
                    label: const Text('상대 프로필 보기'),
                  ),
                ),

                // 승부 결과 입력 버튼 (CHAT / CONFIRMED 상태에서 표시)
                // 포기 버튼은 제거 — 매칭 성사 후 승/패/무만 존재
                if (match.isChat || match.isConfirmed) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => _navigateToGameResult(context, match),
                      icon: const Icon(Icons.emoji_events_rounded, size: 18),
                      label: const Text('승부 결과 입력'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],

                // 의의 제기 버튼 (COMPLETED 상태에서 표시)
                if (match.status == 'COMPLETED') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/disputes/create?matchId=${match.id}'),
                      icon: const Icon(Icons.gavel, size: 18),
                      label: const Text('의의 제기'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
                ],

                // 매칭 취소 버튼 (PENDING_ACCEPT 상태에서만 표시 — CHAT/CONFIRMED는 결과 입력 버튼으로 대체)
                if (match.isPendingAccept) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isCancelling
                          ? null
                          : () => _cancelMatch(context),
                      icon: _isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('매칭 취소'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 승부 결과 입력 화면 이동
  void _navigateToGameResult(BuildContext context, Match match) {
    if (match.gameId != null) {
      context.go('/games/${match.gameId}/result');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('아직 경기가 생성되지 않았습니다.')),
      );
    }
  }

  void _showOpponentProfile(BuildContext context, MatchOpponent opponent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => OpponentProfileSheet(opponent: opponent),
    );
  }

  void _showConfirmMatchDialog(BuildContext context) {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    final venueController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('경기 확정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '경기 날짜',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      selectedDate != null
                          ? '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}'
                          : '날짜를 선택해주세요',
                      style: TextStyle(
                        color: selectedDate != null
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '경기 시간',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      setDialogState(() => selectedTime = time);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      selectedTime != null
                          ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                          : '시간을 선택해주세요',
                      style: TextStyle(
                        color: selectedTime != null
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '장소',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: venueController,
                  decoration: const InputDecoration(
                    hintText: '장소명을 입력해주세요',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (selectedDate == null ||
                          selectedTime == null ||
                          venueController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                              content: Text('날짜, 시간, 장소를 모두 입력해주세요.')),
                        );
                        return;
                      }

                      setDialogState(() => isSubmitting = true);

                      try {
                        final repo = ref.read(matchingRepositoryProvider);
                        final dateStr =
                            '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';
                        final timeStr =
                            '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}';

                        await repo.confirmMatch(
                          widget.matchId,
                          scheduledDate: dateStr,
                          scheduledTime: timeStr,
                          venueName: venueController.text.trim(),
                        );

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('경기가 확정되었습니다.')),
                          );
                          ref.invalidate(matchDetailProvider(widget.matchId));
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('경기 확정 실패: ${e.toString()}')),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('확정'),
            ),
          ],
        ),
      ),
    ).then((_) => venueController.dispose());
  }

  Future<void> _cancelMatch(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('매칭 취소'),
        content: const Text('이 매칭을 취소하시겠습니까?\n취소 후에는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.cancelMatch(widget.matchId, reason: '사용자 취소');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('매칭이 취소되었습니다.')),
        );
        // 매칭 목록으로 이동하고 목록 갱신
        context.go('/matches');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 실패: ${e.toString()}')),
        );
      }
      if (mounted) setState(() => _isCancelling = false);
    }
  }
}

/// VS 레이아웃 헤더
class _VSHeader extends StatelessWidget {
  final Match match;

  const _VSHeader({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryColor, AppTheme.primaryDark],
        ),
      ),
      child: Row(
        children: [
          // 내 프로필 (좌측)
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '나',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    match.sportTypeDisplayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // VS 텍스트
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),

          // 상대 프로필 (우측)
          Expanded(
            child: Column(
              children: [
                UserAvatar(
                  imageUrl: match.opponent.profileImageUrl,
                  size: 64,
                  nickname: match.opponent.nickname,
                ),
                const SizedBox(height: 8),
                Text(
                  match.opponent.nickname,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 상태 배너
class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'PENDING_ACCEPT':
        color = Colors.orange;
        label = '수락 대기 중';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'CHAT':
        color = AppTheme.primaryColor;
        label = '채팅 진행 중';
        icon = Icons.chat_bubble_rounded;
        break;
      case 'CONFIRMED':
        color = AppTheme.secondaryColor;
        label = '경기 확정됨';
        icon = Icons.check_circle_rounded;
        break;
      case 'COMPLETED':
        color = const Color(0xFF6B7280);
        label = '경기 완료';
        icon = Icons.sports_score_rounded;
        break;
      default:
        color = AppTheme.textDisabled;
        label = status;
        icon = Icons.info_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// 매칭 정보 카드
class _MatchInfoCard extends StatelessWidget {
  final Match match;

  const _MatchInfoCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.sports_score_rounded,
            label: '종목',
            value: match.sportTypeDisplayName,
          ),
          if (match.scheduledDate != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              label: '경기 날짜',
              value: match.scheduledDate!,
            ),
          ],
          if (match.scheduledTime != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.access_time_rounded,
              label: '경기 시간',
              value: match.scheduledTime!,
            ),
          ],
          if (match.venueName != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: '장소',
              value: match.venueName!,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppTheme.primaryColor),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
