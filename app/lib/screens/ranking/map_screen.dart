import 'dart:math' as math;
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/pin_provider.dart';
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
  NLatLng _currentLocation = const NLatLng(37.5665, 126.9780);
  bool _hasLocation = false;
  bool _locationDenied = false;
  bool _mapReady = false;
  Pin? _selectedPin;
  List<Pin>? _lastPins;
  bool _didAutoNavigateToFavoritePin = false;

  // 클러스터링 관련
  double _currentZoom = 11.0;
  static final Map<int, NOverlayImage> _clusterIconCache = {};


  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _locationDenied = true);
      return;
    }

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
      if (mounted) setState(() => _locationDenied = true);
      return;
    }

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
      // 자주가는 핀으로 이미 이동했으면 GPS 위치로 덮어쓰지 않음
      if (!_didAutoNavigateToFavoritePin) {
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13),
        );
      }
    } catch (e) {
      debugPrint('[Map] Location error: $e');
    }
  }

  void _showLocationSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: const Color(0xFF4F46E5).withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.location_on_outlined, color: Color(0xFF4F46E5), size: 28),
            ),
            const SizedBox(height: 16),
            const Text('위치 권한 필요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('주변 핀을 표시하려면 위치 권한이 필요합니다.\n설정에서 위치 권한을 허용해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.6)),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFF2A2A2A)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('취소', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); Geolocator.openAppSettings(); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
                ),
                child: const Text('설정으로 이동', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              )),
            ]),
          ],
        ),
      ),
    );
  }

  // ─── 클러스터링 ───────────────────────────────────────────────────

  /// 줌 레벨에 따른 클러스터 반경 (도 단위)
  double _clusterRadius() {
    if (_currentZoom >= 13) return 0;
    if (_currentZoom >= 11) return 0.008;
    if (_currentZoom >= 9) return 0.03;
    if (_currentZoom >= 7) return 0.15;
    if (_currentZoom >= 5) return 0.7;
    return 1.5;
  }

  /// 그리드 기반 클러스터링 (레퍼런스 앱 mongol-community/places_map_page 패턴)
  List<_ClusterOrPin> _computeClusters(List<Pin> pins) {
    final radius = _clusterRadius();
    if (radius == 0) return pins.map((p) => _ClusterOrPin(pin: p)).toList();

    final results = <_ClusterOrPin>[];
    final used = List.filled(pins.length, false);

    for (int i = 0; i < pins.length; i++) {
      if (used[i]) continue;
      final group = <Pin>[pins[i]];
      used[i] = true;
      for (int j = i + 1; j < pins.length; j++) {
        if (used[j]) continue;
        final dx = pins[i].centerLatitude - pins[j].centerLatitude;
        final dy = pins[i].centerLongitude - pins[j].centerLongitude;
        if (math.sqrt(dx * dx + dy * dy) < radius) {
          group.add(pins[j]);
          used[j] = true;
        }
      }
      if (group.length == 1) {
        results.add(_ClusterOrPin(pin: group.first));
      } else {
        final avgLat = group.fold<double>(0, (s, p) => s + p.centerLatitude) / group.length;
        final avgLng = group.fold<double>(0, (s, p) => s + p.centerLongitude) / group.length;
        results.add(_ClusterOrPin(clusterLat: avgLat, clusterLng: avgLng, clusterCount: group.length, pins: group));
      }
    }
    return results;
  }

  /// 클러스터 원형 아이콘 Canvas 렌더링
  /// 레퍼런스 앱 크기(100/120/130/140/160) 대비 1.5배: 150/180/195/210/240
  static Future<NOverlayImage> _createClusterIcon(int count) async {
    final cached = _clusterIconCache[count];
    if (cached != null) return cached;

    final double size = count >= 50 ? 240 : (count >= 20 ? 210 : (count >= 10 ? 195 : (count >= 5 ? 180 : 150)));
    final double fontSize = count >= 50 ? 72 : (count >= 20 ? 66 : (count >= 10 ? 60 : (count >= 5 ? 54 : 48)));

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final r = size / 2;

    // 외곽 글로우
    canvas.drawCircle(center, r, Paint()..color = AppTheme.primaryColor.withValues(alpha: 0.25));
    // 메인 원
    canvas.drawCircle(center, r - 9, Paint()..color = AppTheme.primaryColor);

    // 숫자
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr, textAlign: TextAlign.center);
    textPainter.text = TextSpan(
      text: count > 99 ? '99+' : '$count',
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: Colors.white),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final icon = await NOverlayImage.fromByteArray(byteData!.buffer.asUint8List());
    _clusterIconCache[count] = icon;
    return icon;
  }

  // ─── 마커 ─────────────────────────────────────────────────────────

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
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: PinDetailSheet(pin: pin),
          ),
        ),
      ),
    );
  }

  void _addPinMarkers(List<Pin> pins) async {
    if (!_mapReady || _mapController == null || !mounted) return;

    _mapController!.clearOverlays();
    final clusters = _computeClusters(pins);

    for (final item in clusters) {
      if (!mounted) return;
      if (item.isCluster) {
        final icon = await _createClusterIcon(item.clusterCount!);
        if (!mounted) return;
        final marker = NMarker(
          id: 'cluster_${item.clusterLat}_${item.clusterLng}',
          position: NLatLng(item.clusterLat!, item.clusterLng!),
          icon: icon,
          anchor: const NPoint(0.5, 0.5),
        );
        marker.setOnTapListener((_) {
          _mapController?.updateCamera(
            NCameraUpdate.scrollAndZoomTo(
              target: NLatLng(item.clusterLat!, item.clusterLng!),
              zoom: _currentZoom + 2,
            ),
          );
        });
        _mapController!.addOverlay(marker);
      } else {
        final pin = item.pin!;
        final isSelected = pin.id == _selectedPin?.id;
        final width = (pin.name.length * 14.0 + 32).clamp(70.0, 220.0);
        const height = 46.0;
        final icon = await NOverlayImage.fromWidget(
          widget: SizedBox(
            width: width, height: height,
            child: SportPinMarker(label: pin.name, isSelected: isSelected),
          ),
          size: Size(width, height),
          context: context,
        );
        if (!mounted) return;
        final marker = NMarker(
          id: pin.id,
          position: NLatLng(pin.centerLatitude, pin.centerLongitude),
          icon: icon,
          anchor: const NPoint(0.5, 1.0),
        );
        marker.setOnTapListener((_) => _onPinTap(pin));
        _mapController!.addOverlay(marker);
      }
    }

    _lastPins = pins;

    if (!_didAutoNavigateToFavoritePin) {
      final favoritePin = ref.read(selectedPinProvider);
      if (favoritePin != null) {
        _didAutoNavigateToFavoritePin = true;
        // 자주가는 핀 위치로 지도만 이동 (상세 페이지는 열지 않음)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController?.updateCamera(
              NCameraUpdate.scrollAndZoomTo(
                target: NLatLng(favoritePin.centerLatitude, favoritePin.centerLongitude),
                zoom: 14,
              ),
            );
          }
        });
      }
      // favoritePin이 null이면 _didAutoNavigateToFavoritePin은 false 유지
      // → ref.listen에서 로드 완료 시 이동
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
        userLocation: _hasLocation ? _currentLocation : null,
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

    ref.listen(allPinsProvider, (_, next) {
      next.whenData((pins) {
        if (mounted && _mapReady) _addPinMarkers(pins);
      });
    });

    return Scaffold(
      body: Stack(
        children: [
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(target: _currentLocation, zoom: _hasLocation ? 13 : 11),
              mapType: NMapType.navi,
              nightModeEnable: true,
              locationButtonEnable: false,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              _mapReady = true;
              controller.setLocationTrackingMode(NLocationTrackingMode.noFollow);
              final pins = pinsAsync.valueOrNull;
              if (pins != null && pins.isNotEmpty) _addPinMarkers(pins);
              // 자주가는 핀이 이미 로드됐으면 그쪽으로, 아니면 내 위치로
              final favoritePin = ref.read(selectedPinProvider);
              if (favoritePin != null && !_didAutoNavigateToFavoritePin) {
                _didAutoNavigateToFavoritePin = true;
                controller.updateCamera(NCameraUpdate.scrollAndZoomTo(
                  target: NLatLng(favoritePin.centerLatitude, favoritePin.centerLongitude),
                  zoom: 14,
                ));
              } else if (_hasLocation) {
                controller.updateCamera(NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13));
              }
            },
            onCameraIdle: () async {
              final pos = await _mapController?.getCameraPosition();
              if (pos == null) return;
              final newZoom = pos.zoom;
              if ((_currentZoom - newZoom).abs() > 0.5) {
                _currentZoom = newZoom;
                final pins = _lastPins ?? pinsAsync.valueOrNull;
                if (pins != null && mounted) _addPinMarkers(pins);
              }
            },
          ),

          // 상단 오버레이
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: const Center(child: Text('P', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final pins = pinsAsync.valueOrNull;
                        if (pins != null) _showSearchSheet(pins);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: const Row(children: [
                          Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 18),
                          SizedBox(width: 8),
                          Text('지역 검색', style: TextStyle(color: AppTheme.textDisabled, fontSize: 14)),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 위치 권한 안내 배너
          if (_locationDenied)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Center(
                    child: GestureDetector(
                      onTap: () => Geolocator.openAppSettings(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orange.shade200),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.location_off, color: Colors.orange, size: 16),
                          SizedBox(width: 8),
                          Text('위치 권한을 허용해주세요 (탭하여 설정)', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 핀 로딩/에러 인디케이터
          pinsAsync.when(
            loading: () => Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                        SizedBox(width: 8),
                        Text('핀 로딩 중...', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            error: (e, _) => Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Center(
                    child: GestureDetector(
                      onTap: () => ref.invalidate(allPinsProvider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50, borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.error_outline, color: Colors.red.shade400, size: 16),
                          const SizedBox(width: 8),
                          const Text('핀 로드 실패 (탭하여 재시도)', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            data: (_) => const SizedBox(),
          ),

          // 현재 위치 버튼
          Positioned(
            right: 16, bottom: 28,
            child: FloatingActionButton.small(
              heroTag: 'location',
              onPressed: _goToMyLocation,
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: _hasLocation ? AppTheme.primaryColor : AppTheme.textSecondary,
              elevation: 6,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // 핀 개수 표시
          if (pinsAsync.valueOrNull != null)
            Positioned(
              left: 16, bottom: 36,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
                ),
                child: Text(
                  '핀 ${pinsAsync.valueOrNull!.length}개',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 클러스터 또는 개별 핀을 나타내는 헬퍼 클래스
class _ClusterOrPin {
  final Pin? pin;
  final double? clusterLat;
  final double? clusterLng;
  final int? clusterCount;
  final List<Pin>? pins;

  _ClusterOrPin({this.pin, this.clusterLat, this.clusterLng, this.clusterCount, this.pins});

  bool get isCluster => clusterCount != null;
}

/// 핀 검색 바텀 시트
class _PinSearchSheet extends StatefulWidget {
  final List<Pin> allPins;
  final void Function(Pin pin) onPinSelected;
  final NLatLng? userLocation;

  const _PinSearchSheet({required this.allPins, required this.onPinSelected, this.userLocation});

  @override
  State<_PinSearchSheet> createState() => _PinSearchSheetState();
}

class _PinSearchSheetState extends State<_PinSearchSheet> {
  final _searchController = TextEditingController();
  List<Pin> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = _sortedByDistance(widget.allPins);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  double _distanceTo(Pin pin) {
    final loc = widget.userLocation;
    if (loc == null) return double.maxFinite;
    const r = 6371.0;
    final dLat = (pin.centerLatitude - loc.latitude) * pi / 180;
    final dLng = (pin.centerLongitude - loc.longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(loc.latitude * pi / 180) * cos(pin.centerLatitude * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  List<Pin> _sortedByDistance(List<Pin> pins) {
    final sorted = List<Pin>.from(pins);
    sorted.sort((a, b) => _distanceTo(a).compareTo(_distanceTo(b)));
    return sorted;
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = _sortedByDistance(widget.allPins);
      } else {
        _filtered = _sortedByDistance(widget.allPins.where((p) => p.name.toLowerCase().contains(query)).toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(children: [
                const Icon(Icons.search_rounded, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('핀 검색', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: AppTheme.textSecondary), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '핀 이름으로 검색',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchController.clear())
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(children: [
                Text('${_filtered.length}개', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다.', style: TextStyle(color: AppTheme.textSecondary)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) {
                        final pin = _filtered[index];
                        return ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.08), shape: BoxShape.circle),
                            child: const Icon(Icons.push_pin_outlined, size: 20, color: AppTheme.primaryColor),
                          ),
                          title: Text(pin.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${pin.levelDisplayName} · 유저 ${pin.userCount}명',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          trailing: const Icon(Icons.chevron_right, color: AppTheme.textDisabled),
                          onTap: () => widget.onPinSelected(pin),
                        );
                      },
                    ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}
