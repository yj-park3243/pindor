import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../providers/team_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/team/team_card.dart';

/// 팀 탭 홈 화면
class TeamHomeScreen extends ConsumerWidget {
  const TeamHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTeamsAsync = ref.watch(myTeamsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('팀'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/teams/create'),
            tooltip: '팀 만들기',
          ),
        ],
      ),
      body: myTeamsAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(
          message: '팀 목록을 불러올 수 없습니다.',
          onRetry: () => ref.read(myTeamsProvider.notifier).refresh(),
        ),
        data: (teams) => RefreshIndicator(
          onRefresh: () => ref.read(myTeamsProvider.notifier).refresh(),
          child: teams.isEmpty
              ? _EmptyTeamView(
                  onCreateTeam: () => context.push('/teams/create'),
                  onExplore: () => context.push('/teams/nearby'),
                )
              : _TeamList(
                  teams: teams,
                  onCreateTeam: () => context.push('/teams/create'),
                  onExplore: () => context.push('/teams/nearby'),
                ),
        ),
      ),
    );
  }
}

class _TeamList extends StatelessWidget {
  final List teams;
  final VoidCallback onCreateTeam;
  final VoidCallback onExplore;

  const _TeamList({
    required this.teams,
    required this.onCreateTeam,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // 액션 버튼 영역
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCreateTeam,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('팀 만들기'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExplore,
                  icon: const Icon(Icons.explore, size: 18),
                  label: const Text('주변 팀 탐색'),
                ),
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            '내 팀',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        ...teams.map((team) => TeamCard(
              team: team,
              onTap: () => context.push('/teams/${team.id}'),
            )),
      ],
    );
  }
}

class _EmptyTeamView extends StatelessWidget {
  final VoidCallback onCreateTeam;
  final VoidCallback onExplore;

  const _EmptyTeamView({
    required this.onCreateTeam,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_outlined,
                size: 50,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '아직 소속된 팀이 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '팀을 만들거나 주변 팀에 가입해보세요',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCreateTeam,
                icon: const Icon(Icons.add),
                label: const Text('팀 만들기'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onExplore,
                icon: const Icon(Icons.explore),
                label: const Text('주변 팀 탐색'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
