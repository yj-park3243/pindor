import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/ranking_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/ranking/ranking_list_tile.dart';
import '../../widgets/common/user_avatar.dart';

/// 핀 랭킹 전체 목록 화면
/// 상위 3명: 금/은/동 메달 디자인, 나머지: 리스트 타일
class PinRankingScreen extends ConsumerWidget {
  final String pinId;

  const PinRankingScreen({super.key, required this.pinId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(pinRankingProvider(pinId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: rankingAsync.when(
          data: (data) => Text(data.pin.name),
          loading: () => const Text('랭킹'),
          error: (_, __) => const Text('랭킹'),
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: rankingAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(
          message: '랭킹을 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(pinRankingProvider(pinId)),
        ),
        data: (data) {
          if (data.rankings.isEmpty) {
            return const EmptyState(
              icon: Icons.leaderboard_rounded,
              title: '아직 랭킹이 없습니다',
              subtitle: '이 지역에서 경기를 3판 이상 완료하면\n랭킹에 등록됩니다.',
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // 내 순위 카드
                if (data.myRank != null)
                  _MyRankCard(
                      rank: data.myRank!.rank,
                      score: data.myRank!.score),

                const SizedBox(height: 8),

                // 상위 3명 메달 디자인
                if (data.rankings.length >= 3)
                  _Top3Podium(rankings: data.rankings.take(3).toList()),

                const SizedBox(height: 8),

                // 나머지 랭킹 (4위~)
                if (data.rankings.length > 3)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: data.rankings
                          .skip(3)
                          .map((entry) {
                        final isMe = entry.userId == currentUser?.id;
                        return RankingListTile(entry: entry, isMe: isMe);
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 상위 3명 포디엄 디자인
class _Top3Podium extends StatelessWidget {
  final List<dynamic> rankings;

  const _Top3Podium({required this.rankings});

  @override
  Widget build(BuildContext context) {
    // 순서: 2위(왼쪽), 1위(가운데/높게), 3위(오른쪽)
    final order = rankings.length >= 3
        ? [rankings[1], rankings[0], rankings[2]]
        : rankings;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF1557B0)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2위
          if (rankings.length > 1) ...[
            Expanded(
              child: _PodiumItem(
                entry: order.length > 0 ? order[0] : null,
                rank: 2,
                height: 80,
                medalColor: AppTheme.silverColor,
              ),
            ),
          ],
          // 1위 (가운데, 더 높게)
          Expanded(
            child: _PodiumItem(
              entry: rankings.isNotEmpty ? rankings[0] : null,
              rank: 1,
              height: 100,
              medalColor: AppTheme.goldColor,
              isWinner: true,
            ),
          ),
          // 3위
          if (rankings.length > 2) ...[
            Expanded(
              child: _PodiumItem(
                entry: order.length > 2 ? order[2] : null,
                rank: 3,
                height: 68,
                medalColor: AppTheme.bronzeColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PodiumItem extends StatelessWidget {
  final dynamic entry;
  final int rank;
  final double height;
  final Color medalColor;
  final bool isWinner;

  const _PodiumItem({
    required this.entry,
    required this.rank,
    required this.height,
    required this.medalColor,
    this.isWinner = false,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) return const SizedBox();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 왕관 (1위만)
        if (isWinner)
          const Icon(Icons.emoji_events_rounded,
              size: 28, color: AppTheme.goldColor),
        if (!isWinner) const SizedBox(height: 28),

        const SizedBox(height: 4),

        // 아바타
        UserAvatar(
          imageUrl: entry.profileImageUrl,
          size: isWinner ? 56 : 46,
          nickname: entry.nickname,
        ),

        const SizedBox(height: 8),

        // 닉네임
        Text(
          entry.nickname,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 4),

        // 점수
        Text(
          '${entry.score}점',
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 11,
          ),
        ),

        const SizedBox(height: 8),

        // 포디엄 기단
        Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: medalColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MyRankCard extends StatelessWidget {
  final int rank;
  final int score;

  const _MyRankCard({required this.rank, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppTheme.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '내 순위',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$rank위',
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 1,
            height: 32,
            color: const Color(0xFF2A2A2A),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '현재 점수',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
              Text(
                '$score점',
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
