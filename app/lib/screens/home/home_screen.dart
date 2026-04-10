import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/matching_provider.dart';
import '../../providers/notice_provider.dart';
import '../../providers/notification_provider.dart';
import '../profile/profile_screen.dart' show selectedPinProvider;
import '../../providers/sport_preference_provider.dart';
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
                        Icon(Icons.flash_on_rounded,
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
                        Icon(Icons.arrow_forward_ios,
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

              // ─── 최근 전적 ───
              _RecentMatchHistory(),

              const SizedBox(height: 22),

              // ─── 게시판 최신글 ───
              _PinBoardPreview(),

              const SizedBox(height: 32),
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

          final sportDisplayName = _sportDisplayName(selectedSport);

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
                      _StatItem(
                        icon: Icons.emoji_events_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        label: '순위',
                        value: profile != null ? '미집계' : '-',
                      ),
                      const VerticalDivider(
                        width: 24,
                        thickness: 1,
                        color: Color(0xFF2A2A2A),
                      ),
                      _StatItem(
                        icon: Icons.star_rounded,
                        iconColor: AppTheme.primaryColor,
                        label: '점수',
                        value: profile == null
                            ? '-'
                            : profile.isPlacement
                                ? '배치중'
                                : '${profile.displayScore ?? profile.currentScore}점',
                      ),
                      const VerticalDivider(
                        width: 24,
                        thickness: 1,
                        color: Color(0xFF2A2A2A),
                      ),
                      _StatItem(
                        icon: Icons.people_rounded,
                        iconColor: const Color(0xFF10B981),
                        label: '활동 중',
                        value: '${pin.userCount}명',
                      ),
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
                              Icons.arrow_forward_ios,
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

  String _sportDisplayName(String sportType) {
    switch (sportType) {
      case 'GOLF':
        return '골프';
      case 'BILLIARDS':
        return '당구';
      case 'TENNIS':
        return '테니스';
      case 'TABLE_TENNIS':
        return '탁구';
      default:
        return sportType;
    }
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
                  Icons.arrow_forward_ios,
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
                  Icons.arrow_forward_ios,
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
      onTap: () => context.go('/pins/$pinId/posts/$postId'),
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
                  for (int i = 0; i < matches.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    _MatchHistoryTile(match: matches[i]),
                  ],
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

/// 최근 전적 개별 타일
class _MatchHistoryTile extends StatelessWidget {
  final Match match;

  const _MatchHistoryTile({required this.match});

  @override
  Widget build(BuildContext context) {
    final result = match.gameResult; // WIN | LOSS | DRAW | null
    final isWin = result == 'WIN';
    final isLoss = result == 'LOSS';
    final isDraw = result == 'DRAW';

    Color resultColor;
    String resultText;
    if (isWin) {
      resultColor = const Color(0xFF2563EB);
      resultText = '승';
    } else if (isLoss) {
      resultColor = const Color(0xFFDC2626);
      resultText = '패';
    } else if (isDraw) {
      resultColor = const Color(0xFF9CA3AF);
      resultText = '무';
    } else {
      resultColor = const Color(0xFF9CA3AF);
      resultText = '-';
    }

    final dateStr = _formatDate(match.completedAt ?? match.createdAt);

    return InkWell(
      onTap: () => context.go('${AppRoutes.matchList}/${match.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // 승/패/무 뱃지
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: resultColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                resultText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: resultColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 상대 아바타
            UserAvatar(
              imageUrl: match.opponent.profileImageUrl,
              size: 36,
              nickname: match.opponent.nickname,
            ),
            const SizedBox(width: 10),
            // 상대 닉네임 + 종목/날짜
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          match.opponent.nickname,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (match.isCasual) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            '친선',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${match.sportTypeDisplayName} · $dateStr',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: AppTheme.textDisabled,
            ),
          ],
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
