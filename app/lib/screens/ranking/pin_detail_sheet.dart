import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/ranking_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/ranking/ranking_list_tile.dart';

/// 핀 선택 바텀시트
/// - 핀 이름 + 스포츠 선택 드롭다운
/// - 매칭 신청 버튼
/// - 게시판 / 전체 랭킹 바로가기
/// - 해당 핀 랭킹 TOP 10
class PinDetailSheet extends ConsumerStatefulWidget {
  final Pin pin;

  const PinDetailSheet({super.key, required this.pin});

  @override
  ConsumerState<PinDetailSheet> createState() => _PinDetailSheetState();
}

class _PinDetailSheetState extends ConsumerState<PinDetailSheet> {
  late String _selectedSport;

  @override
  void initState() {
    super.initState();
    _selectedSport = ref.read(sportPreferenceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final rankingAsync = ref.watch(pinRankingBySportProvider((pinId: widget.pin.id, sportType: _selectedSport)));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들 (1개만)
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF444444),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 핀 이름 + 활동 인원
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.pin.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.group, size: 13, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.pin.userCount}명 활동 중',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 스포츠 선택 칩 (Wrap으로 여러 줄 표시)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allSports.map((sport) {
              final isSelected = _selectedSport == sport.value;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedSport = sport.value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFF2A2A2A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sport.icon,
                        size: 14,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        sport.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // 매칭 헤더 + 안내
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8, right: 2),
            child: Row(
              children: [
                const Text(
                  '매칭 신청',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _showMatchInfoDialog(context),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 매칭 신청 — 카드형 CTA (랭크 / 친선)
          Row(
            children: [
              Expanded(
                child: _MatchCtaCard(
                  icon: Icons.leaderboard,
                  title: '랭크 매칭',
                  subtitle: '점수 반영',
                  color: AppTheme.primaryColor,
                  filled: true,
                  onTap: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push('/matches/create?pinId=${widget.pin.id}&pinName=${Uri.encodeComponent(widget.pin.name)}&sportType=$_selectedSport');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MatchCtaCard(
                  icon: Icons.handshake_outlined,
                  title: '친선 매칭',
                  subtitle: '부담없이',
                  color: Colors.orange.shade700,
                  filled: false,
                  onTap: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push('/matches/create?pinId=${widget.pin.id}&pinName=${Uri.encodeComponent(widget.pin.name)}&sportType=$_selectedSport&casual=true');
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 게시판 / 전체 랭킹 — 좌우 균등 큰 버튼
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.forum_outlined,
                  label: '게시판',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/pins/${widget.pin.id}/board');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.leaderboard,
                  label: '전체 랭킹',
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/map/ranking/${widget.pin.id}');
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // TOP 10 랭킹
          const Text(
            'TOP 10',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 10),

          // 랭킹 리스트 (스크롤 불가 — 부모 DraggableSheet이 스크롤 담당)
          rankingAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: LoadingIndicator(),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('랭킹을 불러올 수 없습니다.', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
            data: (rankingData) {
              final top10 = rankingData.rankings.take(10).toList();
              if (top10.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('아직 랭킹 데이터가 없습니다.', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                );
              }

              return Column(
                children: top10.map((entry) {
                  return RankingListTile(
                    entry: entry,
                    isMe: rankingData.myRank?.userId != null &&
                        rankingData.myRank?.userId == entry.userId,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showMatchInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppTheme.primaryColor),
                    SizedBox(width: 6),
                    Text(
                      '매칭 안내',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _MatchInfoSection(
                  color: AppTheme.primaryColor,
                  icon: Icons.leaderboard,
                  title: '랭크 매칭',
                  bullets: [
                    '점수와 승무패가 저장되고 랭킹에 반영됩니다.',
                    '경기 시간을 선택하여 매칭 요청 가능.',
                  ],
                ),
                const SizedBox(height: 12),
                _MatchInfoSection(
                  color: Colors.orange.shade700,
                  icon: Icons.handshake_outlined,
                  title: '친선 매칭',
                  bullets: const [
                    '랭킹에 반영되지 않습니다.',
                    '경기 시간 · 나이 · 성별을 지정해 매칭 요청 가능.',
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('확인'),
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

// ─── 매칭 안내 다이얼로그 섹션 ───
class _MatchInfoSection extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final List<String> bullets;

  const _MatchInfoSection({
    required this.color,
    required this.icon,
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 12, height: 1.4)),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 매칭 CTA 카드 (아이콘 + 제목 + 서브텍스트) ───
class _MatchCtaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _MatchCtaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = filled ? Colors.white : color;
    final Color bg = filled ? color : color.withValues(alpha: 0.08);
    final Color border = filled ? color : color.withValues(alpha: 0.35);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: filled
                      ? Colors.white.withValues(alpha: 0.18)
                      : color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: filled ? Colors.white.withValues(alpha: 0.8) : fg.withValues(alpha: 0.75),
                        height: 1.1,
                      ),
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
}

// ─── 보조 액션 버튼 (좌우 균등 분할용, 큰 사이즈) ───
class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardDark,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
