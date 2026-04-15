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
import '../../widgets/team/team_member_tile.dart';
import '../../widgets/team/team_match_card.dart';
import '../team/team_board_screen.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';

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
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: List.generate(_tabs.length, (i) {
                    final selected = _tabIndex == i;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _tabIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).primaryColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.25),
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
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
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
    final confirmed = await showModalBottomSheet<bool>(
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
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.exit_to_app_outlined,
                  color: Colors.red, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              '팀 나가기',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '정말 이 팀을 나가시겠습니까?\n탈퇴 후에는 다시 가입 요청을 해야 합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF2A2A2A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('취소',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('나가기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(teamRepositoryProvider).leaveTeam(widget.teamId);
        ref.invalidate(myTeamsProvider);
        if (mounted) {
          AppToast.success('팀을 탈퇴했습니다.');
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(extractErrorMessage(e, '팀 탈퇴에 실패했습니다.'));
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
              color: AppTheme.primaryColor.withOpacity(0.2),
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
                  '${team.currentMembers}/${team.maxMembers}명',
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
        color: AppTheme.primaryColor.withOpacity(0.2),
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

