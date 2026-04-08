import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/sports_profile.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/score_display.dart';


/// 스포츠 프로필 관리 화면
/// - 등록된 스포츠별 카드 (전적 + 매칭 문구)
/// - 매칭 문구: 매칭 시 상대에게 보이는 한줄 소개
/// - 새 종목 추가 버튼 (AppBar +)
class SportsProfileScreen extends ConsumerWidget {
  const SportsProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(sportsProfilesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('스포츠 프로필'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '종목 추가',
            onPressed: () => _showAddSportSheet(context, ref),
          ),
        ],
      ),
      body: profilesAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('프로필을 불러올 수 없습니다.'),
              TextButton(
                onPressed: () => ref.invalidate(sportsProfilesProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (profiles) {
          if (profiles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sports_outlined, size: 64, color: AppTheme.textDisabled),
                    const SizedBox(height: 16),
                    const Text('등록된 스포츠 프로필이 없습니다',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('아래 버튼을 눌러 종목을 추가해보세요.',
                        style: TextStyle(color: AppTheme.textSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showAddSportSheet(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('종목 추가'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              return _SportProfileCard(
                profile: profiles[index],
                onEditMessage: () =>
                    _showEditMessageSheet(context, ref, profiles[index]),
              );
            },
          );
        },
      ),
    );
  }

  // ─── 매칭 문구 수정 바텀시트 ───
  void _showEditMessageSheet(
      BuildContext context, WidgetRef ref, SportsProfile profile) {
    final controller = TextEditingController(text: profile.matchMessage ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(sportIcon(profile.sportType), size: 20, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  '${sportLabel(profile.sportType)} 매칭 문구',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '매칭 시 상대방에게 보이는 한줄 소개입니다.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: '예: 주말 라운딩 좋아합니다!',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final msg = controller.text.trim();
                  try {
                    await ref.read(sportsProfilesProvider.notifier).updateProfile(
                      profile.id,
                      matchMessage: msg,
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('매칭 문구가 저장되었습니다.')),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('저장 실패: $e')),
                      );
                    }
                  }
                },
                child: const Text('저장'),
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  // ─── 새 종목 추가 바텀시트 ───
  void _showAddSportSheet(BuildContext context, WidgetRef ref) {
    // 이미 등록된 종목 목록
    final existingTypes = ref.read(sportsProfilesProvider).value
        ?.map((p) => p.sportType)
        .toSet() ?? {};

    // 추가 가능한 종목 목록
    const allSports = ['GOLF', 'BILLIARDS', 'TENNIS', 'TABLE_TENNIS'];
    final availableSports = allSports.where((s) => !existingTypes.contains(s)).toList();

    if (availableSports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 종목이 이미 등록되어 있습니다.')),
      );
      return;
    }

    String? selectedSport = availableSports.first;
    final messageController = TextEditingController();
    final handicapController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '종목 추가',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),

                // 종목 선택
                const Text('종목', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: availableSports.map((sport) {
                    final isSelected = selectedSport == sport;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sportIcon(sport), size: 14,
                              color: isSelected ? Colors.white : AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(sportLabel(sport)),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (_) => setState(() => selectedSport = sport),
                      selectedColor: AppTheme.primaryColor,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 매칭 문구
                const Text('매칭 문구 (선택)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: '매칭 시 상대방에게 보이는 한줄 소개',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),

                // G핸디 (골프 전용)
                if (selectedSport == 'GOLF') ...[
                  const Text('G핸디 (선택)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: handicapController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0 ~ 54 사이 입력',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixText: 'G핸디',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (selectedSport == null) return;
                      final msg = messageController.text.trim();
                      double? gHandicap;
                      if (selectedSport == 'GOLF' && handicapController.text.isNotEmpty) {
                        gHandicap = double.tryParse(handicapController.text.trim());
                        if (gHandicap != null && (gHandicap < 0 || gHandicap > 54)) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('G핸디는 0~54 사이여야 합니다.')),
                          );
                          return;
                        }
                      }
                      try {
                        await ref.read(sportsProfilesProvider.notifier).createProfile(
                          sportType: selectedSport!,
                          matchMessage: msg.isNotEmpty ? msg : null,
                          gHandicap: gHandicap,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${sportLabel(selectedSport!)} 프로필이 추가되었습니다.')),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('추가 실패: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('추가'),
                  ),
                ),
                SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SportProfileCard extends StatelessWidget {
  final SportsProfile profile;
  final VoidCallback onEditMessage;

  const _SportProfileCard({
    required this.profile,
    required this.onEditMessage,
  });

  @override
  Widget build(BuildContext context) {
    final winRate = profile.gamesPlayed > 0
        ? (profile.wins / profile.gamesPlayed * 100).toStringAsFixed(1)
        : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: AppTheme.primaryColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 상단: 종목 + 점수
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(sportIcon(profile.sportType), size: 22, color: AppTheme.primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sportLabel(profile.sportType),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      if (profile.displayName.isNotEmpty)
                        Text(
                          profile.displayName,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
                ScoreText(
                  score: profile.displayScore ?? profile.currentScore,
                  isPlacement: profile.isPlacement,
                  placementGamesRemaining: profile.placementGamesRemaining,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryColor,
                ),
              ],
            ),
          ),

          // 전적 바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat('경기', '${profile.gamesPlayed}'),
                _Stat('승', '${profile.wins}', color: AppTheme.secondaryColor),
                _Stat('패', '${profile.losses}', color: AppTheme.errorColor),
                _Stat('무', '${profile.gamesPlayed - profile.wins - profile.losses}'),
                _Stat('승률', '$winRate%', color: AppTheme.primaryColor),
              ],
            ),
          ),

          // 매너 점수 표시 (평가가 있는 경우에만)
          if (profile.mannerScore != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '매너 ${profile.mannerScore!.toStringAsFixed(1)}/5.0',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 24, indent: 16, endIndent: 16),

          // 매칭 문구 영역
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 14),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    profile.matchMessage != null && profile.matchMessage!.isNotEmpty
                        ? profile.matchMessage!
                        : '매칭 문구를 설정해보세요',
                    style: TextStyle(
                      fontSize: 13,
                      color: profile.matchMessage != null && profile.matchMessage!.isNotEmpty
                          ? AppTheme.textPrimary
                          : AppTheme.textDisabled,
                      fontStyle: profile.matchMessage == null || profile.matchMessage!.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: onEditMessage,
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('수정', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color ?? AppTheme.textPrimary)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }
}
