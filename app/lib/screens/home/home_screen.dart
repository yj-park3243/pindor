import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/router.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/matching_provider.dart';
import '../../providers/notice_provider.dart';
import '../../providers/notification_provider.dart';
import '../profile/profile_screen.dart' show selectedPinProvider;
import '../../providers/socket_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../providers/ranking_provider.dart';
import '../../providers/pin_provider.dart';
import '../../models/match.dart';
import '../../models/pin.dart';
import '../../models/post.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/pin_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/user_avatar.dart';
import 'package:timeago/timeago.dart' as timeago;

/// 최근 완료된 매칭 (최대 5개) 프로바이더
final recentCompletedMatchesProvider =
    FutureProvider.autoDispose<List<Match>>((ref) async {
  final repo = ref.read(matchingRepositoryProvider);
  final matches = await repo.getMyMatches(status: 'COMPLETED', limit: 5);
  return matches;
});

/// 사용자의 자주 가는 핀 프로바이더.
/// 마이페이지에서 설정한 selectedPinProvider를 참조한다.
final userPrimaryPinProvider = Provider.autoDispose<AsyncValue<Pin?>>((ref) {
  final pin = ref.watch(selectedPinProvider);
  return AsyncValue.data(pin);
});

/// 사용자 핀의 최신 게시글 (최대 3개) 프로바이더
final pinLatestPostsProvider =
    FutureProvider.autoDispose.family<List<PinPost>, String>((ref, pinId) async {
  final repo = ref.read(pinRepositoryProvider);
  final result = await repo.getPosts(pinId);
  final posts = (result['data'] as List<dynamic>)
      .map((e) => PinPost.fromJson(e as Map<String, dynamic>))
      .toList();
  return posts.take(3).toList();
});

/// 홈 피드 화면 (PRD SCREEN-010)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 소켓으로 MATCH_PENDING_ACCEPT 알림이 오면 배너를 즉시 갱신
    ref.listen(socketNotificationProvider, (prev, next) {
      next.whenData((data) {
        final type = data['type'] as String?;
        if (type == 'MATCH_PENDING_ACCEPT') {
          ref.invalidate(pendingAcceptMatchesProvider);
        } else if (type == 'MATCH_COMPLETED' ||
            type == 'MATCH_FORFEIT' ||
            type == 'MATCH_FORFEIT_WIN') {
          // 경기 완료/포기 → 점수/순위/전적 즉시 갱신
          ref.invalidate(myRankingHistoryProvider);
          ref.invalidate(recentCompletedMatchesProvider);
          ref.invalidate(pinRankingBySportProvider);
        } else if (type == 'MATCH_REJECTED') {
          // 거절 -5점 페널티 → 점수/순위 갱신 (경기 기록은 아님)
          ref.invalidate(myRankingHistoryProvider);
          ref.invalidate(pinRankingBySportProvider);
        }
      });
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: _PindorAppBar(
        onNotificationTap: () => context.go(AppRoutes.notifications),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(matchRequestProvider);
          ref.invalidate(pendingAcceptMatchesProvider);
          ref.invalidate(userPrimaryPinProvider);
          ref.invalidate(recentCompletedMatchesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── 매칭 수락 대기 배너 ───
              _PendingAcceptBanner(),

              // ─── 진행 중 매칭 + 대기 중 요청 카드 ───
              _ActiveMatchSummary(),

              const SizedBox(height: 8),

              // ─── 공지사항 배너 ───
              _PinnedNoticeBanner(),

              // ─── 오늘 대결 버튼 ───
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => context.go(AppRoutes.map),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.38),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '오늘 대결 나가고 싶다!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '핀 기반 즉시 매칭',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white70, size: 16),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ─── 내 핀 상태 카드 ───
              _MyPinStatusCard(),

              const SizedBox(height: 22),

              // ─── 점수 추이 그래프 ───
              _ScoreTrendChart(),

              const SizedBox(height: 22),

              // ─── 최근 전적 ───
              _RecentMatchHistory(),

              const SizedBox(height: 22),

              // ─── 게시판 최신글 ───
              _PinBoardPreview(),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

/// 핀돌 앱바
class _PindorAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onNotificationTap;

  const _PindorAppBar({required this.onNotificationTap});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return AppBar(
      backgroundColor: const Color(0xFF0A0A0A),
      elevation: 0,
      titleSpacing: 20,
      title: const Text(
        '핀돌',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: AppTheme.primaryColor,
          letterSpacing: 0.5,
        ),
      ),
      actions: [
        // 알림 아이콘 + 빨간 뱃지
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: AppTheme.textPrimary,
              ),
              onPressed: onNotificationTap,
            ),
            if (unreadCount > 0)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.errorColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// 내 핀 상태 카드
/// 즐겨찾기 핀의 순위, 점수, 활동유저, 전적을 한눈에 보여준다.
class _MyPinStatusCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinAsync = ref.watch(userPrimaryPinProvider);
    final user = ref.watch(currentUserProvider);
    final selectedSport = ref.watch(sportPreferenceProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: pinAsync.when(
        loading: () => Container(
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
          ),
          child: const LoadingIndicator(),
        ),
        error: (_, __) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
          ),
          child: const Center(
            child: Text(
              '핀 정보를 불러올 수 없습니다.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
        data: (pin) {
          if (pin == null) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              ),
              child: const Center(
                child: Text(
                  '내 핀을 설정해주세요.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }

          // 선택된 스포츠에 맞는 프로필 찾기
          final profile = user?.sportsProfiles
              .where((p) => p.sportType == selectedSport && p.isActive)
              .firstOrNull;

          final sportDisplayName = sportLabel(selectedSport);

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 핀명 + 종목
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      pin.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 12,
                      color: const Color(0xFFD1D5DB),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sportDisplayName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 통계 행: 순위 | 점수 | 활동 중
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Builder(builder: (context) {
                        final rankAsync = ref.watch(pinRankingBySportProvider(
                          (pinId: pin.id, sportType: selectedSport),
                        ));
                        final myRank = rankAsync.valueOrNull?.myRank;
                        return _StatItem(
                          icon: Icons.emoji_events_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          label: '순위',
                          value: myRank != null ? '${myRank.rank}위' : '-',
                        );
                      }),
                      const VerticalDivider(
                        width: 24,
                        thickness: 1,
                        color: Color(0xFF2A2A2A),
                      ),
                      Builder(builder: (context) {
                        final rankAsync2 = ref.watch(pinRankingBySportProvider(
                          (pinId: pin.id, sportType: selectedSport),
                        ));
                        final myRank2 = rankAsync2.valueOrNull?.myRank;
                        return _StatItem(
                          icon: Icons.star_rounded,
                          iconColor: AppTheme.primaryColor,
                          label: '점수',
                          value: myRank2 != null ? '${myRank2.score}점' : '-',
                        );
                      }),
                      const VerticalDivider(
                        width: 24,
                        thickness: 1,
                        color: Color(0xFF2A2A2A),
                      ),
                      Builder(builder: (context) {
                        final pinDetailAsync = ref.watch(pinDetailProvider(pin.id));
                        final freshPin = pinDetailAsync.valueOrNull;
                        return _StatItem(
                          icon: Icons.people_rounded,
                          iconColor: const Color(0xFF10B981),
                          label: '활동 중',
                          value: '${freshPin?.userCount ?? pin.userCount}명',
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 태그/버튼 행: 배치중 | 게시판
                Row(
                  children: [
                    const Spacer(),

                    // 배치중 태그
                    if (profile != null && profile.isPlacement) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          '배치 중 (${5 - (profile.placementGamesRemaining ?? 5)}/5)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),

                    // 게시판 버튼
                    GestureDetector(
                      onTap: () =>
                          context.go('/pins/${pin.id}/board'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '게시판',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: AppTheme.primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

}

/// 통계 항목 위젯 (순위/점수/활동유저 각 셀)
class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 핀 게시판 최신글 미리보기
/// 사용자 주 핀 + 선택 종목 기반으로 최신 게시글을 표시한다.
class _PinBoardPreview extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinAsync = ref.watch(userPrimaryPinProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '게시판 최신 글',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        pinAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(height: 120, child: LoadingIndicator()),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _emptyPostsBox('게시글을 불러올 수 없습니다.'),
          ),
          data: (pin) {
            if (pin == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _emptyPostsBox('핀을 설정해주세요.'),
              );
            }
            return _PinPostsList(pinId: pin.id);
          },
        ),
      ],
    );
  }

  Widget _emptyPostsBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// 특정 핀의 최신 게시글 목록
class _PinPostsList extends ConsumerWidget {
  final String pinId;

  const _PinPostsList({required this.pinId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(pinLatestPostsProvider(pinId));

    return postsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(height: 120, child: LoadingIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
          ),
          child: const Center(
            child: Text(
              '게시글을 불러올 수 없습니다.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
      ),
      data: (posts) {
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              ),
              child: const Center(
                child: Text(
                  '아직 게시글이 없습니다.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < posts.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16),
                _PreviewTile(
                  title: posts[i].title,
                  author: posts[i].authorNickname,
                  time: timeago.format(posts[i].createdAt, locale: 'ko'),
                  commentCount: posts[i].commentCount,
                  sport: posts[i].categoryDisplayName,
                  postId: posts[i].id,
                  pinId: pinId,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// PENDING_ACCEPT 상태 매칭이 있을 때 상단 배너
class _PendingAcceptBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingAcceptMatchesProvider);

    return pendingAsync.maybeWhen(
      data: (matches) {
        if (matches.isEmpty) return const SizedBox.shrink();
        final first = matches.first;
        return GestureDetector(
          onTap: () =>
              context.go('/matches/${first.id}/accept'),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // 깜빡이는 아이콘 표시
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sports_score_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '매칭 수락 대기중!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (first.isCasual) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade400,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '친선',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${first.opponent.nickname}님과의 매칭을 확인하세요',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white70,
                  size: 14,
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 진행 중 매칭(CHAT/CONFIRMED) + 매칭 요청 큐(WAITING) 요약 카드
/// — 홈 화면에서 한눈에 활성 매칭 상태 파악 + 매칭 탭으로 빠른 진입
class _ActiveMatchSummary extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchListAsync = ref.watch(matchListProvider(null));
    final requestsAsync = ref.watch(matchRequestProvider);

    final activeMatches = matchListAsync.valueOrNull
            ?.where((m) => m.isChat || m.isConfirmed)
            .toList() ??
        const [];
    final waitingRequests = requestsAsync.valueOrNull?.sent
            .where((r) => r.isWaiting)
            .toList() ??
        const [];

    if (activeMatches.isEmpty && waitingRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          for (final m in activeMatches) ...[
            _ActiveMatchCard(match: m),
            const SizedBox(height: 8),
          ],
          for (final r in waitingRequests) ...[
            _WaitingRequestSummaryCard(request: r),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ActiveMatchCard extends StatelessWidget {
  final Match match;
  const _ActiveMatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final statusLabel = match.isChat ? '채팅 중' : '경기 확정';
    final accent = match.isChat ? const Color(0xFF34C759) : AppTheme.primaryColor;
    final scheduled = match.scheduledDate != null
        ? '${match.scheduledDate}${match.scheduledTime != null ? ' ${match.scheduledTime}' : ''}'
        : null;

    return GestureDetector(
      onTap: () => context.go('/matches/${match.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: Row(
          children: [
            UserAvatar(
              imageUrl: match.opponent.profileImageUrl,
              size: 40,
              nickname: match.opponent.nickname,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          match.opponent.nickname,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      sportLabel(match.sportType),
                      if (match.pinName != null) match.pinName!,
                      if (scheduled != null) scheduled,
                    ].join(' · '),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.textDisabled, size: 14),
          ],
        ),
      ),
    );
  }
}

class _WaitingRequestSummaryCard extends StatelessWidget {
  final dynamic request; // MatchRequest
  const _WaitingRequestSummaryCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final pinLabel = (request.pinName as String?) ??
        (request.locationName as String?) ??
        '핀 미지정';
    final sport = sportLabel(request.sportType as String);
    final timeSlot = request.timeSlotDisplayName as String;
    final dateLabel = (request.desiredDate as String?) ?? '날짜 미정';

    return GestureDetector(
      onTap: () => context.go(AppRoutes.matchList),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: Colors.amber.shade600, width: 4)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.amber.shade600.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_rounded,
                  color: Colors.amber.shade600, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade600.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('상대 찾는 중',
                            style: TextStyle(
                                color: Colors.amber.shade600,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          pinLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sport · $dateLabel · $timeSlot',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.textDisabled, size: 14),
          ],
        ),
      ),
    );
  }
}

/// 고정 공지사항 배너
/// 고정 공지가 있을 때 메가폰 아이콘과 첫 번째 공지 제목을 표시한다.
class _PinnedNoticeBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedAsync = ref.watch(pinnedNoticesProvider);

    return pinnedAsync.maybeWhen(
      data: (notices) {
        if (notices.isEmpty) return const SizedBox.shrink();
        final first = notices.first;
        return GestureDetector(
          onTap: () => context.push('/notices/${first.id}'),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFCD34D),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.campaign_rounded,
                  size: 20,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '[공지] ${first.title}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: Color(0xFFD97706),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final String title;
  final String author;
  final String time;
  final int commentCount;
  final String sport;
  final String postId;
  final String pinId;

  const _PreviewTile({
    required this.title,
    required this.author,
    required this.time,
    required this.commentCount,
    required this.sport,
    required this.postId,
    required this.pinId,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/pins/$pinId/board/posts/$postId'),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            // 종목 태그
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sport,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$author · $time',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(
                  '$commentCount',
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
    );
  }
}

/// 최근 전적 섹션
/// 점수 추이 차트
class _ScoreTrendChart extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profile = user?.primarySportsProfile;

    if (profile == null) return const SizedBox.shrink();

    final historyAsync = ref.watch(myRankingHistoryProvider(profile.id));

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (history) {
        if (history.length < 2) return const SizedBox.shrink();

        final spots = <FlSpot>[];
        for (var i = 0; i < history.length; i++) {
          spots.add(FlSpot(i.toDouble(), history[i].score.toDouble()));
        }

        final scores = history.map((h) => h.score).toList();
        final minScore = scores.reduce(math.min);
        final maxScore = scores.reduce(math.max);
        final padding = ((maxScore - minScore) * 0.2).clamp(30, 200).toDouble();
        final yMin = (minScore - padding).floorToDouble();
        final yMax = (maxScore + padding).ceilToDouble();

        final lastScore = history.last.score;
        final firstScore = history.first.score;
        final diff = lastScore - firstScore;
        final isUp = diff > 0;
        final chartColor = isUp
            ? const Color(0xFF10B981)
            : diff < 0
                ? const Color(0xFFEF4444)
                : const Color(0xFF6B7280);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '점수 추이',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '$lastScore점',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: chartColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: chartColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${isUp ? '+' : ''}$diff',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: chartColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 120,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: (spots.length - 1).toDouble(),
                      minY: yMin,
                      maxY: yMax,
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.45,
                          preventCurveOverShooting: true,
                          color: chartColor,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                chartColor.withValues(alpha: 0.25),
                                chartColor.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentMatchHistory extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(recentCompletedMatchesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '최근 전적',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              GestureDetector(
                onTap: () => context.go(
                  AppRoutes.matchList,
                  extra: {'initialTab': 1},
                ),
                child: const Text(
                  '전체보기',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        matchesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(height: 100, child: LoadingIndicator()),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _emptyMatchBox('전적을 불러올 수 없습니다.'),
          ),
          data: (matches) {
            if (matches.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _emptyMatchBox('최근 전적이 없습니다.'),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  for (final match in matches)
                    _MatchHistoryTile(match: match),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _emptyMatchBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// 최근 전적 개별 타일 (매칭 목록 카드와 동일 스타일)
class _MatchHistoryTile extends StatelessWidget {
  final Match match;

  const _MatchHistoryTile({required this.match});

  @override
  Widget build(BuildContext context) {
    final result = match.gameResult;
    final tierColor = AppTheme.tierColor(match.opponent.tier);

    // 상태 액센트 색상
    Color accentColor;
    if (match.isCompleted && result != null) {
      accentColor = result == 'WIN'
          ? const Color(0xFF10B981)
          : result == 'LOSS'
              ? const Color(0xFFEF4444)
              : const Color(0xFF6B7280);
    } else {
      accentColor = const Color(0xFFD1D5DB);
    }

    // 결과 텍스트
    String resultText;
    Color resultBgColor;
    Color resultTextColor;
    if (result == 'WIN') {
      resultText = '승리';
      resultBgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
      resultTextColor = const Color(0xFF10B981);
    } else if (result == 'LOSS') {
      resultText = '패배';
      resultBgColor = const Color(0xFFEF4444).withValues(alpha: 0.15);
      resultTextColor = const Color(0xFFEF4444);
    } else if (result == 'DRAW') {
      resultText = '무승부';
      resultBgColor = const Color(0xFF6B7280).withValues(alpha: 0.15);
      resultTextColor = const Color(0xFF6B7280);
    } else if (result == 'DISPUTED') {
      resultText = '분쟁중';
      resultBgColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      resultTextColor = const Color(0xFFF59E0B);
    } else if (result == 'NO_RESULT') {
      resultText = '결과없음';
      resultBgColor = const Color(0xFF6B7280).withValues(alpha: 0.15);
      resultTextColor = const Color(0xFF6B7280);
    } else {
      resultText = '진행중';
      resultBgColor = AppTheme.primaryColor.withValues(alpha: 0.15);
      resultTextColor = AppTheme.primaryColor;
    }

    final dateStr = _formatDate(match.completedAt ?? match.createdAt);

    return GestureDetector(
      onTap: () => context.push('${AppRoutes.matchList}/${match.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              accentColor.withValues(alpha: 0.12),
              const Color(0xFF1A1A1A),
            ],
          ),
          border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 아바타 + 티어 테두리
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tierColor.withValues(alpha: 0.5), width: 2),
                ),
                child: UserAvatar(
                  imageUrl: match.opponent.profileImageUrl,
                  size: 48,
                  nickname: match.opponent.nickname,
                ),
              ),
              const SizedBox(width: 12),

              // 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 닉네임 + 티어 + 결과
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            match.opponent.nickname,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!match.opponent.isPlacement) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: tierColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(match.opponent.tier, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tierColor)),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: resultBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(resultText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: resultTextColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // 종목 + 날짜 + 핀 + 랭크/친선 칩
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: (match.isCasual ? Colors.orange : AppTheme.secondaryColor)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            match.isCasual ? '친선' : '랭크',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: match.isCasual
                                  ? Colors.orange.shade300
                                  : AppTheme.secondaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(sportIcon(match.sportType), size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 3),
                        Text(match.sportTypeDisplayName, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        Text(' · $dateStr', style: const TextStyle(fontSize: 11, color: AppTheme.textDisabled)),
                        if (match.pinName != null) ...[
                          Text(' · ', style: const TextStyle(fontSize: 11, color: AppTheme.textDisabled)),
                          Flexible(child: Text(match.pinName!, style: const TextStyle(fontSize: 11, color: AppTheme.textDisabled), overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    if (diff < 7) return '$diff일 전';
    return '${date.month}/${date.day}';
  }
}
