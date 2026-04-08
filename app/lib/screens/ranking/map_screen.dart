import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/pin_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../widgets/map/sport_marker.dart';
import '../profile/profile_screen.dart';
import 'pin_detail_sheet.dart';

/// 핀 지도 탭 화면
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  NaverMapController? _mapController;
  NLatLng _currentLocation = const NLatLng(37.5665, 126.9780); // 서울 기본
  bool _hasLocation = false;
  bool _locationDenied = false;
  bool _mapReady = false;
  Pin? _selectedPin;
  List<Pin>? _lastPins;

  // 즐겨찾기 핀 자동 이동 여부 (한 번만 실행)
  bool _didAutoNavigateToFavoritePin = false;

  static const double _defaultRadius = 30.0; // 30km로 넓게

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    // 1. 위치 서비스 활성화 확인
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _locationDenied = true);
      }
      // 서비스 비활성화여도 기본 좌표로 핀은 로드
      return;
    }

    // 2. 권한 확인
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _locationDenied = true);
        _showLocationSettingsDialog();
      }
      return;
    }

    if (permission == LocationPermission.denied) {
      if (mounted) {
        setState(() => _locationDenied = true);
      }
      return;
    }

    // 3. 위치 가져오기
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = NLatLng(pos.latitude, pos.longitude);
        _hasLocation = true;
        _locationDenied = false;
      });
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13),
      );
    } catch (e) {
      debugPrint('[Map] Location error: $e');
    }
  }

  void _showLocationSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('위치 권한 필요'),
        content: const Text('주변 핀을 표시하려면 위치 권한이 필요합니다.\n설정에서 위치 권한을 허용해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }

  void _onPinTap(Pin pin) {
    setState(() => _selectedPin = pin);
    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(pin.centerLatitude, pin.centerLongitude),
        zoom: 14,
      ),
    );
    _showPinDetail(pin);
  }

  void _showPinDetail(Pin pin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              child: PinDetailSheet(pin: pin),
            ),
          );
        },
      ),
    ).whenComplete(() {
      setState(() => _selectedPin = null);
    });
  }

  void _addPinMarkers(List<Pin> pins) async {
    if (!_mapReady || _mapController == null || !mounted) return;

    final sportType = ref.read(sportPreferenceProvider);
    try {
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
    } catch (e) {
      debugPrint('[MapScreen] 마커 생성 실패: $e');
    }

    _lastPins = pins;

    // 즐겨찾기 핀으로 자동 이동 (핀 마커가 모두 추가된 후 한 번만 실행)
    if (!_didAutoNavigateToFavoritePin) {
      _didAutoNavigateToFavoritePin = true;
      final favoritePin = ref.read(selectedPinProvider);
      if (favoritePin != null) {
        // 즐겨찾기 핀이 현재 핀 목록에 있는지 확인
        final matchingPin = pins.where((p) => p.id == favoritePin.id).firstOrNull;
        final targetPin = matchingPin ?? favoritePin;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController?.updateCamera(
              NCameraUpdate.scrollAndZoomTo(
                target: NLatLng(targetPin.centerLatitude, targetPin.centerLongitude),
                zoom: 14,
              ),
            );
            _showPinDetail(targetPin);
          }
        });
      }
    }
  }

  void _goToMyLocation() async {
    if (_hasLocation) {
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13),
      );
    } else {
      await _initLocation();
    }
  }

  void _showSearchSheet(List<Pin> allPins) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PinSearchSheet(
        allPins: allPins,
        onPinSelected: (pin) {
          Navigator.of(sheetContext).pop();
          _onPinTap(pin);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinsAsync = ref.watch(allPinsProvider);

    // 핀 데이터가 도착하면 마커 추가
    ref.listen(
      allPinsProvider,
      (_, next) {
        next.whenData((pins) {
          if (mounted && _mapReady) {
            _addPinMarkers(pins);
          }
        });
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          // 네이버 지도
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _currentLocation,
                zoom: _hasLocation ? 13 : 11,
              ),
              mapType: NMapType.basic,
              locationButtonEnable: true,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              _mapReady = true;
              // 이미 로드된 핀이 있으면 마커 추가
              final pins = pinsAsync.valueOrNull;
              if (pins != null && pins.isNotEmpty) {
                _addPinMarkers(pins);
              }
              // 위치가 있으면 이동
              if (_hasLocation) {
                controller.updateCamera(
                  NCameraUpdate.scrollAndZoomTo(
                      target: _currentLocation, zoom: 13),
                );
              }
            },
          ),

          // 상단 오버레이
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.primaryDark,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'P',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final pins = pinsAsync.valueOrNull;
                            if (pins != null) {
                              _showSearchSheet(pins);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.search_rounded,
                                    color: AppTheme.textSecondary, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  '지역 검색',
                                  style: TextStyle(
                                    color: AppTheme.textDisabled,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 위치 권한 안내 배너
          if (_locationDenied)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Geolocator.openAppSettings(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orange.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_off, color: Colors.orange, size: 16),
                            SizedBox(width: 8),
                            Text(
                              '위치 권한을 허용해주세요 (탭하여 설정)',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 핀 로딩/에러 인디케이터
          pinsAsync.when(
            loading: () => Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
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
                            '핀 로딩 중...',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            error: (e, _) => Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Center(
                    child: GestureDetector(
                      onTap: () => ref.invalidate(allPinsProvider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade400, size: 16),
                            const SizedBox(width: 8),
                            const Text(
                              '핀 로드 실패 (탭하여 재시도)',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            data: (_) => const SizedBox(),
          ),

          // 우하단 현재 위치 버튼
          Positioned(
            right: 16,
            bottom: 28,
            child: FloatingActionButton.small(
              heroTag: 'location',
              onPressed: _goToMyLocation,
              backgroundColor: Colors.white,
              foregroundColor: _hasLocation
                  ? AppTheme.primaryColor
                  : AppTheme.textSecondary,
              elevation: 6,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // 핀 개수 표시
          if (pinsAsync.valueOrNull != null)
            Positioned(
              left: 16,
              bottom: 36,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  '핀 ${pinsAsync.valueOrNull!.length}개',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 핀 검색 바텀 시트
class _PinSearchSheet extends StatefulWidget {
  final List<Pin> allPins;
  final void Function(Pin pin) onPinSelected;

  const _PinSearchSheet({
    required this.allPins,
    required this.onPinSelected,
  });

  @override
  State<_PinSearchSheet> createState() => _PinSearchSheetState();
}

class _PinSearchSheetState extends State<_PinSearchSheet> {
  final _searchController = TextEditingController();
  List<Pin> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.allPins;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.allPins;
      } else {
        _filtered = widget.allPins
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 핸들
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
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text(
                  '핀 검색',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          // 검색 입력
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '핀 이름으로 검색',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 결과 개수
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${_filtered.length}개',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 핀 목록
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text(
                      '검색 결과가 없습니다.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final pin = _filtered[index];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.push_pin_outlined,
                            size: 20,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        title: Text(
                          pin.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${pin.levelDisplayName} · 유저 ${pin.userCount}명',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppTheme.textDisabled,
                        ),
                        onTap: () => widget.onPinSelected(pin),
                      );
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
