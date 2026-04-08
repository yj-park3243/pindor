import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../models/team.dart';
import '../../providers/team_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/team/team_card.dart';

/// 주변 팀 탐색 화면
class NearbyTeamsScreen extends ConsumerStatefulWidget {
  const NearbyTeamsScreen({super.key});

  @override
  ConsumerState<NearbyTeamsScreen> createState() => _NearbyTeamsScreenState();
}

class _NearbyTeamsScreenState extends ConsumerState<NearbyTeamsScreen> {
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  String? _selectedSport;
  bool _showMap = true;

  static const _sports = [
    {'key': '', 'label': '전체'},
    {'key': 'SOCCER', 'label': '축구'},
    {'key': 'BASEBALL', 'label': '야구'},
    {'key': 'BASKETBALL', 'label': '농구'},
    {'key': 'LOL', 'label': 'LoL'},
  ];

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });

      ref.read(nearbyTeamsProvider.notifier).load(
            latitude: position.latitude,
            longitude: position.longitude,
          );
    } catch (e) {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _onSportFilter(String? sportKey) {
    setState(() => _selectedSport = sportKey?.isEmpty == true ? null : sportKey);
    if (_currentPosition != null) {
      ref.read(nearbyTeamsProvider.notifier).filterBySport(_selectedSport);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nearbyState = ref.watch(nearbyTeamsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('주변 팀 탐색'),
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map_outlined),
            onPressed: () => setState(() => _showMap = !_showMap),
            tooltip: _showMap ? '목록 보기' : '지도 보기',
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── 종목 필터 ───
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemCount: _sports.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final sport = _sports[index];
                final key = sport['key']!;
                final isSelected = (key.isEmpty && _selectedSport == null) ||
                    key == _selectedSport;

                return FilterChip(
                  label: Text(sport['label']!),
                  selected: isSelected,
                  onSelected: (_) => _onSportFilter(key),
                  selectedColor: AppTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  checkmarkColor: Colors.white,
                );
              },
            ),
          ),

          // ─── 콘텐츠 영역 ───
          Expanded(
            child: _isLoadingLocation
                ? const FullScreenLoading(message: '위치 정보를 가져오는 중...')
                : _currentPosition == null
                    ? _LocationPermissionView(
                        onRetry: _initLocation,
                      )
                    : _showMap
                        ? _MapView(
                            position: _currentPosition!,
                            teams: nearbyState.teams,
                          )
                        : _TeamListView(
                            teams: nearbyState.teams,
                            isLoading: nearbyState.isLoading,
                          ),
          ),
        ],
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  final Position position;
  final List<Team> teams;

  const _MapView({
    required this.position,
    required this.teams,
  });

  @override
  Widget build(BuildContext context) {
    final center = NLatLng(position.latitude, position.longitude);

    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: center,
          zoom: 13,
        ),
        mapType: NMapType.basic,
      ),
      onMapReady: (controller) {
        // 내 위치 마커
        final myMarker = NMarker(
          id: 'my_location',
          position: center,
          caption: const NOverlayCaption(text: '내 위치'),
        );
        controller.addOverlay(myMarker);

        // 팀 마커
        for (final team in teams) {
          final teamMarker = NMarker(
            id: 'team_${team.id}',
            position: center, // 실제로는 team.latitude, team.longitude 사용
            caption: NOverlayCaption(text: team.name),
          );
          teamMarker.setOnTapListener((_) {
            context.push('/teams/${team.id}');
          });
          controller.addOverlay(teamMarker);
        }
      },
    );
  }
}

class _TeamListView extends StatelessWidget {
  final List<Team> teams;
  final bool isLoading;

  const _TeamListView({required this.teams, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const FullScreenLoading();

    if (teams.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined,
                size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 12),
            const Text(
              '주변에 팀이 없습니다',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: teams.length,
      itemBuilder: (context, index) {
        return TeamCard(
          team: teams[index],
          onTap: () => context.push('/teams/${teams[index].id}'),
          trailing: OutlinedButton(
            onPressed: () => _showJoinDialog(context, teams[index]),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('가입 신청', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  void _showJoinDialog(BuildContext context, Team team) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${team.name} 가입 신청'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${team.name}에 가입을 신청하시겠습니까?'),
            const SizedBox(height: 12),
            Text(
              '${team.currentMembers}/${team.maxMembers}명',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${team.name}에 가입 신청을 보냈습니다.')),
              );
            },
            child: const Text('신청하기'),
          ),
        ],
      ),
    );
  }
}

class _LocationPermissionView extends StatelessWidget {
  final VoidCallback onRetry;

  const _LocationPermissionView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined,
                size: 56, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            const Text(
              '위치 정보를 가져올 수 없습니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '위치 권한을 허용하면 주변 팀을 탐색할 수 있습니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
