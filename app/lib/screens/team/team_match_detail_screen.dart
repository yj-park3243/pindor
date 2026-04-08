import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../models/team.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../repositories/team_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';

/// 팀 매칭 상세 화면
class TeamMatchDetailScreen extends ConsumerWidget {
  final String matchId;

  const TeamMatchDetailScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchAsync = ref.watch(teamMatchDetailProvider(matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('팀 매칭 상세')),
      body: matchAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(
          message: '매칭 정보를 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(teamMatchDetailProvider(matchId)),
        ),
        data: (match) => _MatchDetailContent(match: match, matchId: matchId),
      ),
    );
  }
}

class _MatchDetailContent extends ConsumerStatefulWidget {
  final TeamMatch match;
  final String matchId;

  const _MatchDetailContent({required this.match, required this.matchId});

  @override
  ConsumerState<_MatchDetailContent> createState() =>
      _MatchDetailContentState();
}

class _MatchDetailContentState extends ConsumerState<_MatchDetailContent> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final currentUser = ref.watch(currentUserProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 상태 배너 ───
          _StatusBanner(status: match.status),
          const SizedBox(height: 20),

          // ─── 양 팀 정보 ───
          _TeamsSection(match: match),
          const SizedBox(height: 16),

          // ─── 경기 일정/장소 ───
          if (match.scheduledDate != null ||
              match.scheduledTime != null ||
              match.venueName != null)
            _ScheduleCard(match: match),

          // ─── 메시지 ───
          if (match.message != null) ...[
            const SizedBox(height: 16),
            _MessageCard(message: match.message!),
          ],

          const SizedBox(height: 24),

          // ─── 채팅 버튼 ───
          if (match.chatRoomId != null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    context.push('/team-chats/${match.chatRoomId}'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('단체 채팅'),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ─── 결과 입력 (CONFIRMED 상태) ───
          if (match.isConfirmed) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _showResultDialog(context),
                icon: const Icon(Icons.scoreboard_outlined),
                label: const Text('결과 입력'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showResultDialog(BuildContext context) {
    final homeScoreCtrl = TextEditingController();
    final awayScoreCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('경기 결과 입력'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: homeScoreCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  label: Text(widget.match.homeTeam?.name ?? '홈팀'),
                  hintText: '0',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(':',
                  style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: TextField(
                controller: awayScoreCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  label: Text(widget.match.awayTeam?.name ?? '어웨이팀'),
                  hintText: '0',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _submitResult(
                int.tryParse(homeScoreCtrl.text) ?? 0,
                int.tryParse(awayScoreCtrl.text) ?? 0,
              );
            },
            child: const Text('제출'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitResult(int homeScore, int awayScore) async {
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.submitResult(widget.matchId, {
        'homeScore': homeScore,
        'awayScore': awayScore,
      });
      ref.invalidate(teamMatchDetailProvider(widget.matchId));

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('결과가 제출되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('제출 실패: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'PENDING':
        color = AppTheme.warningColor;
        label = '요청 중';
        icon = Icons.hourglass_empty;
        break;
      case 'ACCEPTED':
        color = AppTheme.primaryColor;
        label = '수락됨';
        icon = Icons.check_circle_outline;
        break;
      case 'CONFIRMED':
        color = AppTheme.secondaryColor;
        label = '경기 확정';
        icon = Icons.sports;
        break;
      case 'COMPLETED':
        color = const Color(0xFF6B7280);
        label = '경기 완료';
        icon = Icons.sports_score;
        break;
      case 'CANCELLED':
        color = AppTheme.errorColor;
        label = '취소됨';
        icon = Icons.cancel_outlined;
        break;
      default:
        color = AppTheme.textSecondary;
        label = status;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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

class _TeamsSection extends StatelessWidget {
  final TeamMatch match;

  const _TeamsSection({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(child: _TeamInfo(team: match.homeTeam, label: '홈')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: match.isCompleted
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${match.homeScore ?? 0}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '${match.awayScore ?? 0}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSecondary,
                    ),
                  ),
          ),
          Expanded(
              child: _TeamInfo(
                  team: match.awayTeam, label: '어웨이', alignRight: true)),
        ],
      ),
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final Team? team;
  final String label;
  final bool alignRight;

  const _TeamInfo({this.team, required this.label, this.alignRight = false});

  @override
  Widget build(BuildContext context) {
    final name = team?.name ?? '팀';
    final logoUrl = team?.logoUrl;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';

    final logo = logoUrl != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorWidget: (c, u, e) => _fallback(initial),
            ),
          )
        : _fallback(initial);

    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        logo,
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _fallback(String initial) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final TeamMatch match;

  const _ScheduleCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          if (match.scheduledDate != null) ...[
            _InfoRow(
              icon: Icons.calendar_today,
              label: '날짜',
              value: match.scheduledDate!,
            ),
          ],
          if (match.scheduledTime != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.access_time,
              label: '시간대',
              value: match.scheduledTime!,
            ),
          ],
          if (match.venueName != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.location_on,
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
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;

  const _MessageCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '메시지',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
