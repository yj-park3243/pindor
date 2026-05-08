import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../models/sports_profile.dart';
import '../../providers/pin_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/ranking_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../providers/user_provider.dart';
import '../profile/profile_screen.dart' show selectedPinProvider;
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';

import '../../widgets/ranking/ranking_list_tile.dart';

/// 내 랭킹 화면 — 참여 핀 + 참여 종목 선택 → 해당 핀/종목 랭킹 표시
class MyRankingScreen extends ConsumerStatefulWidget {
  const MyRankingScreen({super.key});

  @override
  ConsumerState<MyRankingScreen> createState() => _MyRankingScreenState();
}

class _MyRankingScreenState extends ConsumerState<MyRankingScreen> {
  Pin? _selectedPin;
  String? _selectedSport;

  /// 참여한 핀만 정렬 (자주 가는 핀 → 거리순)
  List<Pin> _participatedPins(
    List<Pin> pins,
    Position? position,
    String? favoritePinId,
    Set<String> participatedPinIds,
  ) {
    final filtered = pins
        .where((p) => p.level == 'DONG' && participatedPinIds.contains(p.id))
        .toList();

    Pin? favorite;
    final rest = <Pin>[];
    for (final pin in filtered) {
      if (pin.id == favoritePinId) {
        favorite = pin;
      } else {
        rest.add(pin);
      }
    }

    if (position != null) {
      double distanceTo(Pin pin) => Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            pin.centerLatitude,
            pin.centerLongitude,
          );
      rest.sort((a, b) => distanceTo(a).compareTo(distanceTo(b)));
    } else {
      rest.sort((a, b) => a.name.compareTo(b.name));
    }

    return [
      if (favorite != null) favorite,
      ...rest,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pinsAsync = ref.watch(allPinsProvider);
    final profilesAsync = ref.watch(sportsProfilesProvider);
    final userAsync = ref.watch(userNotifierProvider);
    final userLocation = userAsync.valueOrNull?.location;
    final favoritePin = ref.watch(selectedPinProvider);
    final participatedIds =
        ref.watch(myParticipatedPinIdsProvider).valueOrNull ?? {};
    final preferredSport = ref.watch(sportPreferenceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('내 랭킹'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ─── 핀/종목 선택 (PullDownButton) ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: pinsAsync.when(
                    loading: () => const _SelectorSkeleton(),
                    error: (_, __) => const _SelectorSkeleton(),
                    data: (pins) {
                      Position? position;
                      if (userLocation != null) {
                        position = Position(
                          latitude: userLocation.latitude,
                          longitude: userLocation.longitude,
                          timestamp: DateTime.now(),
                          accuracy: 0,
                          altitude: 0,
                          altitudeAccuracy: 0,
                          heading: 0,
                          headingAccuracy: 0,
                          speed: 0,
                          speedAccuracy: 0,
                        );
                      }

                      final myPins = _participatedPins(
                        pins,
                        position,
                        favoritePin?.id,
                        participatedIds,
                      );

                      // 초기 선택: 첫 항목
                      if (myPins.isNotEmpty &&
                          (_selectedPin == null ||
                              !myPins.any((p) => p.id == _selectedPin!.id))) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _selectedPin = myPins.first);
                        });
                      }

                      return _PinSelector(
                        pins: myPins,
                        selected: _selectedPin,
                        onSelected: (p) => setState(() => _selectedPin = p),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: profilesAsync.when(
                    loading: () => const _SelectorSkeleton(),
                    error: (_, __) => const _SelectorSkeleton(),
                    data: (profiles) {
                      // 초기 선택: 선호 종목이 프로필에 있으면 우선, 없으면 첫 번째
                      if (profiles.isNotEmpty &&
                          (_selectedSport == null ||
                              !profiles
                                  .any((p) => p.sportType == _selectedSport))) {
                        final next = profiles.any(
                                (p) => p.sportType == preferredSport)
                            ? preferredSport
                            : profiles.first.sportType;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _selectedSport = next);
                        });
                      }

                      return _SportSelector(
                        profiles: profiles,
                        selected: _selectedSport,
                        onSelected: (s) => setState(() => _selectedSport = s),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF1A1A1A)),

          // ─── 선택된 핀+종목의 랭킹 ───
          Expanded(
            child: (_selectedPin == null || _selectedSport == null)
                ? const Center(
                    child: Text(
                      '참여한 핀/종목이 없습니다.\n경기를 진행하면 랭킹이 표시됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : _PinRankingBody(
                    pinId: _selectedPin!.id,
                    sportType: _selectedSport!,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 핀 선택 PullDown 트리거
class _PinSelector extends StatelessWidget {
  final List<Pin> pins;
  final Pin? selected;
  final ValueChanged<Pin> onSelected;

  const _PinSelector({
    required this.pins,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = selected?.name ?? '핀 선택';
    return PullDownButton(
      itemBuilder: (context) {
        if (pins.isEmpty) {
          return [
            const PullDownMenuItem(
              title: '참여한 핀이 없습니다',
              enabled: false,
              onTap: null,
            ),
          ];
        }
        return [
          for (final pin in pins)
            PullDownMenuItem.selectable(
              title: pin.name,
              icon: Icons.location_on_rounded,
              selected: selected?.id == pin.id,
              onTap: () => onSelected(pin),
            ),
        ];
      },
      buttonBuilder: (context, showMenu) => _SelectorTrigger(
        icon: Icons.location_on_rounded,
        label: label,
        onTap: showMenu,
      ),
    );
  }
}

/// 종목 선택 PullDown 트리거
class _SportSelector extends StatelessWidget {
  final List<SportsProfile> profiles;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _SportSelector({
    required this.profiles,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = selected != null ? sportLabel(selected!) : '종목 선택';
    final icon = selected != null ? sportIcon(selected!) : Icons.sports_rounded;
    return PullDownButton(
      itemBuilder: (context) {
        if (profiles.isEmpty) {
          return [
            const PullDownMenuItem(
              title: '참여한 종목이 없습니다',
              enabled: false,
              onTap: null,
            ),
          ];
        }
        return [
          for (final profile in profiles)
            PullDownMenuItem.selectable(
              title: sportLabel(profile.sportType),
              icon: sportIcon(profile.sportType),
              selected: selected == profile.sportType,
              onTap: () => onSelected(profile.sportType),
            ),
        ];
      },
      buttonBuilder: (context, showMenu) => _SelectorTrigger(
        icon: icon,
        label: label,
        onTap: showMenu,
      ),
    );
  }
}

class _SelectorTrigger extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SelectorTrigger({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primaryColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorSkeleton extends StatelessWidget {
  const _SelectorSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

/// 선택된 핀+종목의 랭킹 표시
class _PinRankingBody extends ConsumerWidget {
  final String pinId;
  final String sportType;

  const _PinRankingBody({required this.pinId, required this.sportType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync =
        ref.watch(pinRankingBySportProvider((pinId: pinId, sportType: sportType)));

    return rankingAsync.when(
      loading: () => const FullScreenLoading(),
      error: (e, _) => ErrorView(
        message: '랭킹을 불러올 수 없습니다.',
        onRetry: () => ref.invalidate(
          pinRankingBySportProvider((pinId: pinId, sportType: sportType)),
        ),
      ),
      data: (data) {
        final rankings = data.rankings;
        final myRank = data.myRank;

        if (rankings.isEmpty) {
          return const Center(
            child: Text(
              '아직 랭킹 데이터가 없습니다.\n이 핀/종목에서 경기를 완료하면 반영됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }

        return Column(
          children: [
            if (myRank != null)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.1),
                      AppTheme.primaryColor.withValues(alpha: 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${myRank.rank}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '내 순위',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '${myRank.score}점',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: rankings.length,
                itemBuilder: (context, index) {
                  return RankingListTile(
                    entry: rankings[index],
                    isMe: myRank?.userId == rankings[index].userId,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
