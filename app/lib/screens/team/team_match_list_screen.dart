import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../providers/team_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/team/team_match_card.dart';

/// 팀 매칭 목록 화면
class TeamMatchListScreen extends ConsumerStatefulWidget {
  final String teamId;

  const TeamMatchListScreen({super.key, required this.teamId});

  @override
  ConsumerState<TeamMatchListScreen> createState() =>
      _TeamMatchListScreenState();
}

class _TeamMatchListScreenState extends ConsumerState<TeamMatchListScreen> {
  int _selectedIndex = 0;

  static const _tabs = ['진행중', '완료'];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(teamMatchesProvider(widget.teamId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('팀 매칭'),
      ),
      body: Column(
        children: [
          Padding(
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
                  final selected = _selectedIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: selected
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
          Expanded(
            child: state.isLoading
                ? const FullScreenLoading()
                : state.error != null
                    ? ErrorView(
                        message: '매칭 목록을 불러올 수 없습니다.',
                        onRetry: () => ref
                            .read(teamMatchesProvider(widget.teamId).notifier)
                            .refresh(),
                      )
                    : _selectedIndex == 0
                        ? _MatchListView(
                            matches: state.active,
                            teamId: widget.teamId,
                            emptyMessage: '진행중인 팀 매칭이 없습니다',
                          )
                        : _MatchListView(
                            matches: state.completed,
                            teamId: widget.teamId,
                            emptyMessage: '완료된 팀 매칭이 없습니다',
                          ),
          ),
        ],
      ),
    );
  }
}

class _MatchListView extends StatelessWidget {
  final List matches;
  final String teamId;
  final String emptyMessage;

  const _MatchListView({
    required this.matches,
    required this.teamId,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final match = matches[index];
        return TeamMatchCard(
          match: match,
          myTeamId: teamId,
          onTap: () => context.push('/team-matches/${match.id}'),
        );
      },
    );
  }
}
