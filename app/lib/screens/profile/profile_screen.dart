import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../models/sports_profile.dart';
import '../../providers/user_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/pin_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../widgets/map/sport_marker.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/score_display.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('내 프로필'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: '프로필 수정',
          ),
          IconButton(
            onPressed: () => context.push('/profile/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => _ErrorBody(
          onRetry: () => ref.invalidate(userNotifierProvider),
        ),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('사용자 정보를 불러올 수 없습니다.'));
          }

          final primaryProfile = user.primarySportsProfile;

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
                    score: primaryProfile?.displayScore ?? primaryProfile?.currentScore ?? 1000,
                    isPlacement: primaryProfile?.isPlacement ?? false,
                    placementGamesRemaining: primaryProfile?.placementGamesRemaining,
                  ),

                  const SizedBox(height: 16),

                  // ─── 전적 요약 ───
                  if (primaryProfile != null)
                    _RecordSummary(profile: primaryProfile),

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

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}

// ─── 프로필 헤더 ──────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String nickname;
  final String? profileImageUrl;
  final int score;
  final bool isPlacement;
  final int? placementGamesRemaining;

  const _ProfileHeader({
    required this.nickname,
    required this.profileImageUrl,
    required this.score,
    this.isPlacement = false,
    this.placementGamesRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withOpacity(0.12),
            AppTheme.primaryColor.withOpacity(0.04),
          ],
        ),
      ),
      child: Column(
        children: [
          // 아바타
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: profileImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: profileImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                      ),
                    )
                  : Container(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      child: Center(
                        child: Text(
                          nickname.isNotEmpty ? nickname[0] : '?',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            nickname,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (isPlacement)
            ScoreText(
              score: score,
              isPlacement: true,
              placementGamesRemaining: placementGamesRemaining,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
              ),
              child: Text(
                '$score점',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
        ],
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
    final winRate = profile.gamesPlayed > 0
        ? (profile.wins / profile.gamesPlayed * 100).toStringAsFixed(1)
        : '0.0';
    final draws = profile.gamesPlayed - profile.wins - profile.losses;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
              _StatDivider(),
              _StatBox(
                label: '승',
                value: '${profile.wins}',
                color: AppTheme.secondaryColor,
              ),
              _StatDivider(),
              _StatBox(
                label: '무',
                value: '${draws > 0 ? draws : 0}',
                color: AppTheme.textSecondary,
              ),
              _StatDivider(),
              _StatBox(
                label: '패',
                value: '${profile.losses}',
                color: AppTheme.errorColor,
              ),
              _StatDivider(),
              _StatBox(
                label: '승률',
                value: '$winRate%',
                color: AppTheme.primaryColor,
              ),
            ],
          ),
        ],
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
      color: const Color(0xFFE5E7EB),
    );
  }
}

// ─── 스포츠 프로필 섹션 ─────────────────────────────────────────────────────────

class _SportProfileSection extends StatelessWidget {
  final List<SportsProfile> profiles;

  const _SportProfileSection({required this.profiles});

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
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
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '스포츠 프로필',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          ...profiles.map((p) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
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
                        Row(
                          children: [
                            ScoreText(
                              score: p.displayScore ?? p.currentScore,
                              isPlacement: p.isPlacement,
                              placementGamesRemaining: p.placementGamesRemaining,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                            Text(
                              ' · ${p.gamesPlayed}전 ${p.wins}승 ${p.losses}패',
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
                ],
              ),
            );
          }),
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
        subtitle: '서비스 공지 확인',
        onTap: () => context.push('/notices'),
      ),
      _MenuItem(
        icon: Icons.leaderboard_outlined,
        label: '내 랭킹',
        subtitle: '지역 핀 랭킹 확인',
        onTap: () => context.push('/map/my-ranking'),
      ),
      _MenuItem(
        icon: Icons.support_agent_outlined,
        label: '신고/문의',
        subtitle: '문의 및 신고 접수',
        onTap: () => context.push('/profile/inquiry'),
      ),
      _MenuItem(
        icon: Icons.settings_outlined,
        label: '설정',
        subtitle: '앱 환경 설정',
        onTap: () => context.push('/profile/settings'),
      ),
      _MenuItem(
        icon: Icons.privacy_tip_outlined,
        label: '개인정보 처리방침',
        onTap: () => launchUrl(
          Uri.parse('https://pins.kr/privacy.html'),
          mode: LaunchMode.externalApplication,
        ),
      ),
      _MenuItem(
        icon: Icons.description_outlined,
        label: '이용약관',
        onTap: () => launchUrl(
          Uri.parse('https://pins.kr/terms.html'),
          mode: LaunchMode.externalApplication,
        ),
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
        color: Colors.white,
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
                    color: AppTheme.primaryColor.withOpacity(0.08),
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
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;
      setState(() => _currentLocation = NLatLng(pos.latitude, pos.longitude));
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13),
      );
    } catch (e) {
      debugPrint('[PinMapSelection] Location error: $e');
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('자주 가는 핀 선택'),
        backgroundColor: Colors.white,
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
                    locationButtonEnable: true,
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
                        color: Colors.white,
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
                    backgroundColor: Colors.white,
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
              color: Colors.white,
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
                        ? AppTheme.primaryColor.withOpacity(0.06)
                        : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedPin != null
                          ? AppTheme.primaryColor.withOpacity(0.4)
                          : const Color(0xFFE5E7EB),
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
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
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
        color: Colors.white,
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
                color: const Color(0xFFE5E7EB),
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
                        ? AppTheme.primaryColor.withOpacity(0.1)
                        : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : const Color(0xFFE5E7EB),
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
