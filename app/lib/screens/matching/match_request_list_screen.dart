import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/router.dart';
import '../../providers/matching_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/match_card.dart';

/// 매칭 요청 목록 화면 (보낸/받은)
class MatchRequestListScreen extends ConsumerStatefulWidget {
  const MatchRequestListScreen({super.key});

  @override
  ConsumerState<MatchRequestListScreen> createState() =>
      _MatchRequestListScreenState();
}

class _MatchRequestListScreenState
    extends ConsumerState<MatchRequestListScreen> {
  int _selectedIndex = 0;

  static const _tabs = ['받은 요청', '보낸 요청'];

  @override
  Widget build(BuildContext context) {
    final requestState = ref.watch(matchRequestProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('매칭 요청'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AdaptiveSegmentedControl(
              labels: _tabs,
              selectedIndex: _selectedIndex,
              onValueChanged: (index) => setState(() => _selectedIndex = index),
            ),
          ),
          Expanded(
            child: requestState.when(
              loading: () => const FullScreenLoading(),
              error: (e, _) => Center(child: Text('오류: $e')),
              data: (state) => _selectedIndex == 0
                  ? _RequestList(
                      requests: state.received,
                      emptyTitle: '받은 요청이 없습니다',
                      onRefresh: () =>
                          ref.read(matchRequestProvider.notifier).refresh(),
                    )
                  : _RequestList(
                      requests: state.sent,
                      emptyTitle: '보낸 요청이 없습니다',
                      emptySubtitle: '매칭을 요청해보세요!',
                      emptyButtonText: '매칭 요청하기',
                      onEmptyButtonTap: () => context.go(AppRoutes.createMatch),
                      onRefresh: () =>
                          ref.read(matchRequestProvider.notifier).refresh(),
                      showCancelButton: true,
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.createMatch),
        icon: const Icon(Icons.add),
        label: const Text('요청 만들기'),
      ),
    );
  }
}

class _RequestList extends ConsumerWidget {
  final List requests;
  final String emptyTitle;
  final String? emptySubtitle;
  final String? emptyButtonText;
  final VoidCallback? onEmptyButtonTap;
  final Future<void> Function() onRefresh;
  final bool showCancelButton;

  const _RequestList({
    required this.requests,
    required this.emptyTitle,
    this.emptySubtitle,
    this.emptyButtonText,
    this.onEmptyButtonTap,
    required this.onRefresh,
    this.showCancelButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (requests.isEmpty) {
      return EmptyState(
        icon: Icons.sports_golf,
        title: emptyTitle,
        subtitle: emptySubtitle,
        buttonText: emptyButtonText,
        onButtonTap: onEmptyButtonTap,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MatchRequestCard(
              request: request,
              onTap: () => context.go('/matches/${request.id}'),
              showActions: showCancelButton,
            ),
          );
        },
      ),
    );
  }
}
