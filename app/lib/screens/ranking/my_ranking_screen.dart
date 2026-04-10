import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/pin_provider.dart';
import '../../providers/ranking_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';

import '../../widgets/ranking/ranking_list_tile.dart';

/// 내 랭킹 화면 — 핀 선택 → 해당 핀 랭킹 표시
class MyRankingScreen extends ConsumerStatefulWidget {
  const MyRankingScreen({super.key});

  @override
  ConsumerState<MyRankingScreen> createState() => _MyRankingScreenState();
}

class _MyRankingScreenState extends ConsumerState<MyRankingScreen> {
  Pin? _selectedPin;

  /// 한 번이라도 내 랭킹이 확인된 핀 ID 집합 (참여 이력 있는 핀)
  final Set<String> _participatedPinIds = {};

  /// 참여 핀 발견 콜백 — _PinRankingBody에서 호출
  void _onParticipatedPin(String pinId) {
    if (!_participatedPinIds.contains(pinId)) {
      setState(() => _participatedPinIds.add(pinId));
    }
  }

  /// 핀 목록을 정렬: 참여 핀 우선 → 거리순 (위치 없으면 이름순)
  List<Pin> _sortPins(List<Pin> pins, Position? position) {
    final participated = <Pin>[];
    final rest = <Pin>[];

    for (final pin in pins) {
      if (_participatedPinIds.contains(pin.id)) {
        participated.add(pin);
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
      participated.sort((a, b) => distanceTo(a).compareTo(distanceTo(b)));
      rest.sort((a, b) => distanceTo(a).compareTo(distanceTo(b)));
    } else {
      participated.sort((a, b) => a.name.compareTo(b.name));
      rest.sort((a, b) => a.name.compareTo(b.name));
    }

    return [...participated, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    // 전체 핀 로드 (핀 선택지)
    final pinsAsync = ref.watch(allPinsProvider);
    // 유저 위치 (저장된 홈 위치)
    final userAsync = ref.watch(userNotifierProvider);
    final userLocation = userAsync.valueOrNull?.location;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('내 랭킹'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ─── 핀 선택 (가로 스크롤 칩) ───
          pinsAsync.when(
            loading: () => const SizedBox(
              height: 52,
              child: Center(child: LoadingIndicator()),
            ),
            error: (_, __) => const SizedBox(height: 52),
            data: (pins) {
              // DONG 레벨만 필터 후 정렬
              final dongPins = pins.where((p) => p.level == 'DONG').toList();

              // 위치 기반 Position 객체 생성 (user 저장 위치 활용)
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

              final sortedPins = _sortPins(dongPins, position);

              if (sortedPins.isNotEmpty && _selectedPin == null) {
                Future.microtask(
                    () => setState(() => _selectedPin = sortedPins.first));
              }
              return SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: sortedPins.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final pin = sortedPins[index];
                    final isSelected = _selectedPin?.id == pin.id;
                    final isParticipated = _participatedPinIds.contains(pin.id);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedPin = pin),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : const Color(0xFF2A2A2A),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isParticipated
                                  ? Icons.location_on
                                  : Icons.location_on_outlined,
                              size: 14,
                              color: isSelected
                                  ? Colors.white
                                  : isParticipated
                                      ? AppTheme.primaryColor
                                      : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              pin.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const Divider(height: 1),

          // ─── 선택된 핀의 랭킹 ───
          Expanded(
            child: _selectedPin == null
                ? const Center(
                    child: Text(
                      '핀을 선택해주세요',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : _PinRankingBody(
                    pinId: _selectedPin!.id,
                    onParticipated: _onParticipatedPin,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 선택된 핀의 랭킹 표시
class _PinRankingBody extends ConsumerWidget {
  final String pinId;
  /// 이 핀에서 내 랭킹이 확인될 때 호출되는 콜백
  final void Function(String pinId)? onParticipated;

  const _PinRankingBody({required this.pinId, this.onParticipated});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(pinRankingProvider(pinId));

    return rankingAsync.when(
      loading: () => const FullScreenLoading(),
      error: (e, _) => ErrorView(
        message: '랭킹을 불러올 수 없습니다.',
        onRetry: () => ref.invalidate(pinRankingProvider(pinId)),
      ),
      data: (data) {
        final rankings = data.rankings;
        final myRank = data.myRank;

        // 내 랭킹이 있으면 참여 핀으로 기록
        if (myRank != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onParticipated?.call(pinId);
          });
        }

        if (rankings.isEmpty) {
          return const Center(
            child: Text(
              '아직 랭킹 데이터가 없습니다.\n이 핀에서 경기를 완료하면 반영됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }

        return Column(
          children: [
            // 내 순위 카드
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

            // 랭킹 리스트
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
