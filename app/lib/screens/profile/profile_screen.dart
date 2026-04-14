import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/utils/location_utils.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../models/sports_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/pin_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../providers/ranking_provider.dart';
import '../../models/ranking_entry.dart';
import '../../widgets/map/sport_marker.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/fullscreen_image_viewer.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/network/api_client.dart';

/// 자주 가는 핀을 SharedPreferences에 영속 저장하는 프로바이더
class SelectedPinNotifier extends Notifier<Pin?> {
  static const _key = 'selected_pin';

  @override
  Pin? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json != null) {
      try {
        state = Pin.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> select(Pin? pin) async {
    state = pin;
    final prefs = await SharedPreferences.getInstance();
    if (pin != null) {
      await prefs.setString(_key, jsonEncode(pin.toJson()));
      // 서버에 자주 가는 핀 동기화
      try {
        await ApiClient.instance.post('/pins/favorite', body: {'pinId': pin.id});
      } catch (_) {}
    } else {
      await prefs.remove(_key);
    }
  }
}

final selectedPinProvider =
NotifierProvider<SelectedPinNotifier, Pin?>(SelectedPinNotifier.new);

/// 내 프로필 메인 화면 (PRD SCREEN-060)
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userNotifierProvider);
    final profilesAsync = ref.watch(sportsProfilesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: userAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => _ErrorBody(
          onRetry: () => ref.invalidate(userNotifierProvider),
        ),
        data: (user) {
          if (user == null) {
            return _ErrorBody(
              onRetry: () => ref.invalidate(userNotifierProvider),
            );
          }

          final currentSport = ref.watch(sportPreferenceProvider);
          // 현재 선택 종목에 해당하는 프로필 (없으면 null — 다른 종목으로 fallback하지 않음)
          final selectedProfile = user.sportsProfiles
                  .where((p) => p.sportType == currentSport)
                  .firstOrNull;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userNotifierProvider);
              ref.invalidate(sportsProfilesProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // ─── 프로필 헤더 ───
                  _ProfileHeader(
                    nickname: user.nickname,
                    profileImageUrl: user.profileImageUrl,
                    currentSport: currentSport,
                    profile: selectedProfile,
                  ),

                  const SizedBox(height: 16),

                  // ─── 스포츠 프로필 목록 ───
                  profilesAsync.when(
                    loading: () => const LoadingIndicator(),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline, color: Colors.red),
                          title: const Text('스포츠 프로필 로드 실패'),
                          subtitle: Text(e.toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: TextButton(
                            onPressed: () => ref.invalidate(sportsProfilesProvider),
                            child: const Text('재시도'),
                          ),
                        ),
                      ),
                    ),
                    data: (profiles) => _SportProfileSection(
                      profiles: profiles,
                      currentSport: currentSport,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── 메뉴 목록 ───
                  const _ProfileMenu(),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  final VoidCallback onRetry;
  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 52, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text('프로필을 불러올 수 없습니다.'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('다시 시도')),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text(
              '로그아웃',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 프로필 헤더 (홀로그램 카드) ──────────────────────────────────────────────

class _ProfileHeader extends ConsumerStatefulWidget {
  final String nickname;
  final String? profileImageUrl;
  final String currentSport;
  final SportsProfile? profile;

  const _ProfileHeader({
    required this.nickname,
    required this.profileImageUrl,
    required this.currentSport,
    this.profile,
  });

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader>
    with TickerProviderStateMixin {
  double _currentX = 0.5;
  double _currentY = 0.5;
  bool _isTouching = false;

  // 복귀 애니메이션
  late AnimationController _returnController;
  late Animation<double> _returnAnimX;
  late Animation<double> _returnAnimY;

  // 아이들 자동 광원 애니메이션
  late AnimationController _idleController;

  @override
  void initState() {
    super.initState();
    _returnController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..addListener(() {
        setState(() {
          _currentX = _returnAnimX.value;
          _currentY = _returnAnimY.value;
        });
      });

    // 아이들: 4초 주기로 자동 광원 이동
    _idleController = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
    _idleController.addListener(() {
      if (!_isTouching && !_returnController.isAnimating) {
        setState(() {
          // 원형 궤도로 살짝 움직임 (중심 0.5 ± 0.08)
          _currentX = 0.5 + 0.08 * cos(_idleController.value * 2 * pi);
          _currentY = 0.5 + 0.06 * sin(_idleController.value * 2 * pi);
        });
      }
    });
  }

  @override
  void dispose() {
    _returnController.dispose();
    _idleController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size cardSize) {
    final x = (details.localPosition.dx / cardSize.width).clamp(0.0, 1.0);
    final y = (details.localPosition.dy / cardSize.height).clamp(0.0, 1.0);
    setState(() {
      _currentX += (x - _currentX) * 0.3;
      _currentY += (y - _currentY) * 0.3;
      _isTouching = true;
    });
  }

  void _onPanEnd() {
    _isTouching = false;
    _returnAnimX = Tween<double>(begin: _currentX, end: 0.5)
        .animate(CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic));
    _returnAnimY = Tween<double>(begin: _currentY, end: 0.5)
        .animate(CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic));
    _returnController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isPlacement = profile?.isPlacement ?? false;
    final placementGamesRemaining = profile?.placementGamesRemaining;

    // 핀 + 랭킹
    final selectedPin = ref.watch(selectedPinProvider);
    final rankAsync = selectedPin != null
        ? ref.watch(pinRankingBySportProvider((pinId: selectedPin.id, sportType: widget.currentSport)))
        : null;
    final myRank = rankAsync?.valueOrNull?.myRank;

    // 티어: 핀별 랭킹 티어 우선, 없으면 프로필 티어 fallback
    final tier = myRank?.tier ?? profile?.tier;
    final tierColor = tier != null ? AppTheme.tierColor(tier) : AppTheme.primaryColor;

    // 3D 기울기 (최대 ±10도)
    final rotateX = (_currentY - 0.5) * -20.0 * pi / 180;
    final rotateY = (_currentX - 0.5) * 20.0 * pi / 180;

    // 광원 Alignment (-1.6 ~ 1.2 범위)
    final lightAlignX = (_currentX * 2.8) - 1.6;
    final lightAlignY = (_currentY * 2.0) - 1.0;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardSize = Size(constraints.maxWidth, 220);
            return GestureDetector(
              onPanUpdate: (d) => _onPanUpdate(d, cardSize),
              onPanEnd: (_) => _onPanEnd(),
              onPanCancel: _onPanEnd,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0008)
                  ..rotateX(rotateX)
                  ..rotateY(rotateY),
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: tierColor.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        // 배경: 티어색을 강하게 반영
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(const Color(0xFF0F0F1A), tierColor, 0.25)!,
                                Color.lerp(const Color(0xFF1A1A2E), tierColor, 0.10)!,
                                const Color(0xFF0A0A14),
                              ],
                            ),
                          ),
                        ),

                        // 상단 코너 티어색 글로우
                        Positioned(
                          top: -40,
                          right: -40,
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  tierColor.withValues(alpha: 0.15),
                                  tierColor.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 메인 광원 (포인터 따라 이동)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(lightAlignX, lightAlignY),
                                radius: 0.7,
                                colors: [
                                  Colors.white.withValues(alpha: _isTouching ? 0.18 : 0.06),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 티어색 광원 (포인터 따라 이동)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(lightAlignX * 0.8, lightAlignY * 0.8),
                                radius: 1.0,
                                colors: [
                                  tierColor.withValues(alpha: _isTouching ? 0.25 : 0.10),
                                  tierColor.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 카드 컨텐츠
                        Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 상단: 아바타 + 닉네임 + 설정
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: widget.profileImageUrl != null
                                        ? () => showFullscreenImage(context, [widget.profileImageUrl!])
                                        : null,
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: tierColor.withValues(alpha: 0.5), width: 2),
                                      ),
                                      child: ClipOval(
                                        child: widget.profileImageUrl != null
                                            ? CachedNetworkImage(
                                          imageUrl: widget.profileImageUrl!,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => _AvatarFallback(nickname: widget.nickname, color: tierColor),
                                          errorWidget: (_, __, ___) => _AvatarFallback(nickname: widget.nickname, color: tierColor),
                                        )
                                            : _AvatarFallback(nickname: widget.nickname, color: tierColor),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(widget.nickname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(sportIcon(widget.currentSport), size: 12, color: Colors.white54),
                                            const SizedBox(width: 4),
                                            Text(sportLabel(widget.currentSport), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => GoRouter.of(context).push('/profile/settings'),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Symbols.settings_rounded, color: Colors.white54, size: 18),
                                    ),
                                  ),
                                ],
                              ),

                              // 매칭 문구
                              if (profile?.matchMessage != null && profile!.matchMessage!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '"${profile.matchMessage}"',
                                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4), fontStyle: FontStyle.italic),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                              const Spacer(),

                              // 하단: 핀별 점수/등수/티어
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // 좌측: 핀별 점수 + 티어
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (profile == null)
                                          const Text('종목을 추가해주세요', style: TextStyle(fontSize: 14, color: Colors.white38))
                                        else if (selectedPin == null)
                                          const Text('핀을 설정해주세요', style: TextStyle(fontSize: 14, color: Colors.white38))
                                        else if (isPlacement)
                                            Text(
                                              '배치 중 (${5 - (placementGamesRemaining ?? 0)}/5)',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tierColor),
                                            )
                                          else if (myRank != null && myRank.rank > 0) ...[
                                              // 해당 핀에서 플레이 기록 있음 → 핀별 점수
                                              Text('${myRank.score}점', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(color: tierColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                                    child: Text(myRank.tier, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tierColor)),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '${profile.gamesPlayed}전 ${profile.wins}승 ${profile.losses}패',
                                                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.35)),
                                                  ),
                                                ],
                                              ),
                                            ] else
                                            // 해당 핀에서 플레이 기록 없음
                                              Text('${selectedPin.name}에서\n기록이 없습니다', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.35), height: 1.4)),
                                      ],
                                    ),
                                  ),

                                  // 우측: 핀 + 등수
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (selectedPin != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Symbols.location_on_rounded, size: 12, color: Colors.white38),
                                            const SizedBox(width: 3),
                                            Text(selectedPin.name, style: const TextStyle(fontSize: 11, color: Colors.white38)),
                                          ],
                                        ),
                                      if (myRank != null && myRank.rank > 0) ...[
                                        const SizedBox(height: 4),
                                        Text('${myRank.rank}위', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: tierColor, height: 1)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── 전적 요약 ────────────────────────────────────────────────────────────────

class _RecordSummary extends StatelessWidget {
  final SportsProfile profile;

  const _RecordSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.sportTypeDisplayName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _StatBox(
                  label: '전체',
                  value: '${profile.gamesPlayed}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String nickname;
  final Color color;
  const _AvatarFallback({required this.nickname, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          nickname.isNotEmpty ? nickname[0] : '?',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatBox({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
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

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFF2A2A2A),
    );
  }
}

// ─── 스포츠 프로필 섹션 ─────────────────────────────────────────────────────────

class _SportProfileSection extends ConsumerWidget {
  final List<SportsProfile> profiles;
  final String currentSport;

  const _SportProfileSection({required this.profiles, required this.currentSport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPin = ref.watch(selectedPinProvider);

    if (profiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text(
              '매칭을 시작하면 스포츠 프로필이 자동 생성됩니다',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '스포츠 프로필',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => context.push('/profile/sports'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '관리',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 선택 종목 1개만 표시 (나머지는 상세에서)
          ...profiles.where((p) => p.sportType == currentSport).take(1).map((p) {
            return GestureDetector(
              onTap: () => context.push('/profile/sports'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(color: AppTheme.primaryColor, width: 3.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(sportIcon(p.sportType), size: 28, color: AppTheme.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sportLabel(p.sportType),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Builder(builder: (context) {
                            final rankAsync = selectedPin != null
                                ? ref.watch(pinRankingBySportProvider(
                              (pinId: selectedPin.id, sportType: p.sportType),
                            ))
                                : const AsyncValue<PinRankingData>.loading();
                            final myRank = rankAsync.valueOrNull?.myRank;
                            final hasPinRecord = myRank != null && myRank.rank > 0;

                            // 핀별 점수/티어 우선, 없으면 "기록 없음"
                            final pinScore = hasPinRecord ? myRank.score : null;
                            final pinTier = hasPinRecord ? myRank.tier : null;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (selectedPin == null)
                                  const Text('핀을 설정해주세요', style: TextStyle(fontSize: 12, color: AppTheme.textDisabled))
                                else if (hasPinRecord)
                                  Row(
                                    children: [
                                      Text(
                                        '${pinScore}점 · $pinTier',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.tierColor(pinTier!),
                                        ),
                                      ),
                                      Text(
                                        ' · ${myRank.rank}위',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    '${selectedPin.name} 기록 없음',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textDisabled),
                                  ),
                                const SizedBox(height: 1),
                                Text(
                                  hasPinRecord
                                      ? '${selectedPin?.name ?? ''} · ${myRank!.rank}위'
                                      : '${p.gamesPlayed}경기 · ${p.wins}승 ${p.losses}패 (전체)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textDisabled,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (profiles.length > 1) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/profile/sports'),
                icon: const Icon(Icons.sports_esports_outlined, size: 16),
                label: Text('전체 종목 보기 (${profiles.length}개)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 프로필 메뉴 ──────────────────────────────────────────────────────────────

class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPin = ref.watch(selectedPinProvider);
    final currentSport = ref.watch(sportPreferenceProvider);

    final activityItems = [
      _MenuItem(
        icon: Icons.location_on_outlined,
        label: '자주 가는 핀',
        subtitle: selectedPin != null ? selectedPin.name : '핀을 선택해주세요',
        onTap: () => _showPinSelectionSheet(context, ref),
      ),
      _MenuItem(
        icon: Icons.sports_tennis_outlined,
        label: '종목 변경',
        subtitle: _sportDisplayName(currentSport),
        onTap: () => _showSportSelectionSheet(context, ref),
      ),
    ];

    final generalItems = [
      _MenuItem(
        icon: Icons.campaign_outlined,
        label: '공지사항',
        onTap: () => context.push('/notices'),
      ),
      _MenuItem(
        icon: Icons.leaderboard_outlined,
        label: '내 랭킹',
        onTap: () => context.push('/map/my-ranking'),
      ),
      _MenuItem(
        icon: Icons.support_agent_outlined,
        label: '신고/문의',
        onTap: () => context.push('/profile/inquiry'),
      ),
    ];

    final accountItems = [
      _MenuItem(
        icon: Icons.edit_outlined,
        label: '프로필 수정',
        subtitle: '닉네임, 프로필 사진 변경',
        onTap: () => context.push('/profile/edit'),
      ),
      _MenuItem(
        icon: Icons.settings_outlined,
        label: '설정',
        subtitle: '알림, 캐시, 로그아웃',
        onTap: () => context.push('/profile/settings'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── 활동 설정 섹션 ───
        _SectionHeader(title: '활동 설정'),
        _MenuCard(items: activityItems),

        const SizedBox(height: 12),

        // ─── 일반 메뉴 섹션 ───
        _MenuCard(items: generalItems),

        const SizedBox(height: 12),

        // ─── 계정 관리 섹션 ───
        _SectionHeader(title: '계정'),
        _MenuCard(items: accountItems),
      ],
    );
  }

  String _sportDisplayName(String sportType) => sportLabel(sportType);

  void _showPinSelectionSheet(BuildContext context, WidgetRef ref) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PinMapSelectionPage(
          onPinSelected: (pin) {
            ref.read(selectedPinProvider.notifier).select(pin);
            // 핀 변경 시 새 핀의 모든 종목 랭킹 캐시 갱신
            final profiles = ref.read(userNotifierProvider).valueOrNull?.sportsProfiles ?? [];
            for (final p in profiles) {
              ref.invalidate(pinRankingBySportProvider(
                (pinId: pin.id, sportType: p.sportType),
              ));
            }
          },
        ),
      ),
    );
  }

  void _showSportSelectionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => _SportSelectionSheet(
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;

  const _MenuCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children: items.asMap().entries.map((entry) {
          final isLast = entry.key == items.length - 1;
          return Column(
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(entry.value.icon,
                      color: AppTheme.primaryColor, size: 20),
                ),
                title: Text(
                  entry.value.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: entry.value.subtitle != null
                    ? Text(
                  entry.value.subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                )
                    : null,
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textDisabled,
                ),
                onTap: entry.value.onTap,
              ),
              if (!isLast)
                const Divider(height: 1, indent: 72, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });
}

// ─── 핀 선택 바텀 시트 ─────────────────────────────────────────────────────────

class _PinMapSelectionPage extends ConsumerStatefulWidget {
  final void Function(Pin pin) onPinSelected;

  const _PinMapSelectionPage({required this.onPinSelected});

  @override
  ConsumerState<_PinMapSelectionPage> createState() =>
      _PinMapSelectionPageState();
}

class _PinMapSelectionPageState extends ConsumerState<_PinMapSelectionPage> {
  NaverMapController? _mapController;
  bool _mapReady = false;
  NLatLng _currentLocation = const NLatLng(37.5665, 126.9780);
  bool _isLocating = false;
  Pin? _selectedPin;
  List<Pin>? _lastPins;

  @override
  void initState() {
    super.initState();
    _selectedPin = ref.read(selectedPinProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await LocationUtils.getCurrentPosition();
      if (pos == null || !mounted) return;

      setState(() => _currentLocation = NLatLng(pos.latitude, pos.longitude));
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _addPinMarkers(List<Pin> pins) async {
    if (!_mapReady || _mapController == null || !mounted) return;

    final sportType = ref.read(sportPreferenceProvider);
    final markers = await SportMarkerBuilder.buildMarkers(
      context: context,
      pins: pins,
      selectedPinId: _selectedPin?.id,
      sportType: sportType,
      onTap: (pin) => _onPinTap(pin),
    );

    if (!mounted || _mapController == null) return;
    _mapController!.clearOverlays();
    _mapController!.addOverlayAll(markers);
    _lastPins = pins;
  }

  void _onPinTap(Pin pin) {
    setState(() => _selectedPin = pin);
    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(pin.centerLatitude, pin.centerLongitude),
        zoom: 14,
      ),
    );
    if (_lastPins != null) _addPinMarkers(_lastPins!);
  }

  void _confirm() {
    if (_selectedPin == null) return;
    widget.onPinSelected(_selectedPin!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pinsAsync = ref.watch(allPinsProvider);

    ref.listen(allPinsProvider, (_, next) {
      next.whenData((pins) {
        if (mounted && _mapReady) _addPinMarkers(pins);
      });
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('자주 가는 핀 선택'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '지도에서 핀을 탭하여 선택하세요',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                NaverMap(
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                      target: _currentLocation,
                      zoom: 12,
                    ),
                    mapType: NMapType.basic,
                    locationButtonEnable: false,
                  ),
                  onMapReady: (controller) {
                    _mapController = controller;
                    _mapReady = true;
                    final pins = pinsAsync.valueOrNull;
                    if (pins != null && pins.isNotEmpty) {
                      _addPinMarkers(pins);
                    }
                  },
                ),
                if (pinsAsync.isLoading)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '핀 불러오는 중...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'pin_select_location_btn',
                    onPressed: _isLocating ? null : _initLocation,
                    backgroundColor: const Color(0xFF0A0A0A),
                    foregroundColor: AppTheme.primaryColor,
                    elevation: 4,
                    child: _isLocating
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    )
                        : const Icon(Icons.my_location_rounded),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              boxShadow: [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 12,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 선택된 핀 표시
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _selectedPin != null
                        ? AppTheme.primaryColor.withOpacity(0.15)
                        : const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedPin != null
                          ? AppTheme.primaryColor.withOpacity(0.4)
                          : const Color(0xFF2A2A2A),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedPin != null
                            ? Icons.location_on_rounded
                            : Icons.location_off_rounded,
                        size: 18,
                        color: _selectedPin != null
                            ? AppTheme.primaryColor
                            : AppTheme.textDisabled,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedPin?.name ?? '지도에서 핀을 선택해주세요',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _selectedPin != null
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _selectedPin != null
                                ? AppTheme.textPrimary
                                : AppTheme.textDisabled,
                          ),
                        ),
                      ),
                      if (_selectedPin != null)
                        Text(
                          '${_selectedPin!.levelDisplayName} · ${_selectedPin!.userCount}명',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _selectedPin != null ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      disabledBackgroundColor: const Color(0xFF333333),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('선택 완료', style: TextStyle(fontSize: 15)),
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

// ─── 종목 선택 바텀 시트 ───────────────────────────────────────────────────────

class _SportSelectionSheet extends ConsumerWidget {
  final ScrollController? scrollController;
  const _SportSelectionSheet({this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSport = ref.watch(sportPreferenceProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Icon(Icons.sports_outlined, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    '종목 선택',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: allSports.map((sport) {
                final isSelected = currentSport == sport.value;
                return GestureDetector(
                  onTap: () async {
                    await ref
                        .read(sportPreferenceProvider.notifier)
                        .select(sport.value);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withOpacity(0.2)
                          : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : const Color(0xFF2A2A2A),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sport.icon,
                          size: 28,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sport.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ],
        ),
      ),
    );
  }
}
