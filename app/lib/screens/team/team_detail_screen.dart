import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/theme.dart';
import '../../models/team.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../repositories/team_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/team/team_member_tile.dart';
import '../../widgets/team/team_match_card.dart';
import '../team/team_board_screen.dart';

/// 팀 상세 화면
class TeamDetailScreen extends ConsumerWidget {
  final String teamId;

  const TeamDetailScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamDetailProvider(teamId));

    return teamAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const FullScreenLoading(),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: '팀 정보를 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(teamDetailProvider(teamId)),
        ),
      ),
      data: (team) => _TeamDetailView(team: team, teamId: teamId),
    );
  }
}

class _TeamDetailView extends ConsumerStatefulWidget {
  final Team team;
  final String teamId;

  const _TeamDetailView({required this.team, required this.teamId});

  @override
  ConsumerState<_TeamDetailView> createState() => _TeamDetailViewState();
}

class _TeamDetailViewState extends ConsumerState<_TeamDetailView> {
  int _tabIndex = 0;

  static const _tabs = ['경기', '게시판', '채팅'];

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final currentUser = ref.watch(currentUserProvider);
    final membersAsync = ref.watch(teamMembersProvider(widget.teamId));

    // 내 역할 파악
    final myMember = membersAsync.valueOrNull?.firstWhere(
      (m) => m.userId == currentUser?.id,
      orElse: () => TeamMember(
        id: '',
        teamId: widget.teamId,
        userId: '',
        role: '',
        status: '',
        joinedAt: DateTime.now(),
      ),
    );
    final isCaptain = myMember?.isCaptain ?? false;
    final isLeader = myMember?.isLeader ?? false;
    final isMember = myMember != null && myMember.userId.isNotEmpty;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            actions: [
              if (isCaptain)
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      context.push('/teams/${widget.teamId}/manage'),
                  tooltip: '팀 관리',
                ),
              if (isMember && !isCaptain)
                IconButton(
                  icon: const Icon(Icons.exit_to_app),
                  onPressed: () => _showLeaveTeamDialog(context, ref),
                  tooltip: '팀 나가기',
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _TeamHeader(team: team),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AdaptiveSegmentedControl(
                labels: _tabs,
                selectedIndex: _tabIndex,
                onValueChanged: (index) => setState(() => _tabIndex = index),
              ),
            ),
          ),
        ],
        body: IndexedStack(
          index: _tabIndex,
          children: [
            // 경기 탭
            _MatchTab(teamId: widget.teamId, isLeader: isLeader),
            // 게시판 탭
            TeamBoardInlineScreen(teamId: widget.teamId),
            // 채팅 탭
            _ChatTab(teamId: widget.teamId),
          ],
        ),
      ),
      // 하단 멤버 섹션은 AppBar 아래 팀 정보에 포함
    );
  }

  Future<void> _showLeaveTeamDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('팀 나가기'),
        content: const Text('정말 이 팀을 나가시겠습니까?\n탈퇴 후에는 다시 가입 요청을 해야 합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('나가기'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(teamRepositoryProvider).leaveTeam(widget.teamId);
        ref.invalidate(myTeamsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('팀을 탈퇴했습니다.')),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('팀 탈퇴에 실패했습니다: $e')),
          );
        }
      }
    }
  }
}

class _TeamHeader extends StatelessWidget {
  final Team team;

  const _TeamHeader({required this.team});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundLight,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 56,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 팀 로고
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: team.logoUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: team.logoUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      team.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 16),

          // 팀 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  team.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _InfoChip(label: team.sportTypeDisplayName),
                    const SizedBox(width: 6),
                    _InfoChip(label: '${team.teamScore}점'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${team.wins}승 ${team.losses}패 ${team.draws}무  |  ${team.currentMembers}/${team.maxMembers}명',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (team.activityRegion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          team.activityRegion!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }
}

// ─── 경기 탭 ───
class _MatchTab extends ConsumerWidget {
  final String teamId;
  final bool isLeader;

  const _MatchTab({required this.teamId, required this.isLeader});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesState = ref.watch(teamMatchesProvider(teamId));

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(teamMatchesProvider(teamId).notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isLeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push('/teams/$teamId/match/request'),
                icon: const Icon(Icons.add),
                label: const Text('팀 매칭 요청'),
              ),
            ),

          if (matchesState.isLoading)
            const FullScreenLoading()
          else if (matchesState.error != null)
            ErrorView(message: '매칭 목록을 불러올 수 없습니다.')
          else if (matchesState.active.isEmpty && matchesState.completed.isEmpty)
            const _EmptyState(
              icon: Icons.sports,
              message: '진행중인 팀 매칭이 없습니다',
            )
          else ...[
            if (matchesState.active.isNotEmpty) ...[
              const Text(
                '진행중',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...matchesState.active.map((m) => TeamMatchCard(
                    match: m,
                    myTeamId: teamId,
                    onTap: () => context.push('/team-matches/${m.id}'),
                  )),
              const SizedBox(height: 16),
            ],
            if (matchesState.completed.isNotEmpty) ...[
              const Text(
                '완료',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...matchesState.completed.map((m) => TeamMatchCard(
                    match: m,
                    myTeamId: teamId,
                    onTap: () => context.push('/team-matches/${m.id}'),
                  )),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── 채팅 탭 ───
class _ChatTab extends ConsumerWidget {
  final String teamId;

  const _ChatTab({required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(teamChatRoomsProvider(teamId));

    return roomsAsync.when(
      loading: () => const FullScreenLoading(),
      error: (e, _) => const ErrorView(message: '채팅방을 불러올 수 없습니다.'),
      data: (rooms) {
        if (rooms.isEmpty) {
          return const _EmptyState(
            icon: Icons.chat_bubble_outline,
            message: '팀 채팅방이 없습니다',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final room = rooms[index];
            // matchId가 비어있으면 팀 내부 채팅, 있으면 팀 매칭 채팅
            final isInternalChat = room.matchId.isEmpty;
            final displayName = isInternalChat
                ? '팀 채팅'
                : (room.opponent.nickname.isNotEmpty
                    ? room.opponent.nickname
                    : '상대 팀');
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                child: Icon(
                  isInternalChat ? Icons.groups : Icons.sports,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(displayName),
              subtitle: room.lastMessage != null
                  ? Text(
                      room.lastMessage!.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              onTap: () => context.push('/team-chats/${room.id}'),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

