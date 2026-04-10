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
    final rankingAsync = ref.watch(pinRankingProvider(widget.pin.id));

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
                  ref.read(sportPreferenceProvider.notifier).select(sport.value);
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

          // 매칭 신청 버튼 (랭크 / 친선 두 버튼)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.push('/matches/create?pinId=${widget.pin.id}&pinName=${Uri.encodeComponent(widget.pin.name)}&sportType=$_selectedSport');
                    },
                    icon: const Icon(Icons.leaderboard, size: 17),
                    label: const Text(
                      '랭크 매칭',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.push('/matches/create?pinId=${widget.pin.id}&pinName=${Uri.encodeComponent(widget.pin.name)}&sportType=$_selectedSport&casual=true');
                    },
                    icon: Icon(Icons.handshake_outlined, size: 17, color: Colors.orange.shade700),
                    label: Text(
                      '친선 매칭',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.orange.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 게시판 / 랭킹 버튼
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/pins/${widget.pin.id}/board');
                  },
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: const Text('게시판'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/map/ranking/${widget.pin.id}');
                  },
                  icon: const Icon(Icons.leaderboard, size: 16),
                  label: const Text('전체 랭킹'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
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
}
