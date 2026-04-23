import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/location_utils.dart';
import '../../config/router.dart';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/pin_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../widgets/map/sport_marker.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';

/// 자주 가는 핀 + 선호 종목 설정 화면 (온보딩 4단계)
class PinSportSetupScreen extends ConsumerStatefulWidget {
  const PinSportSetupScreen({super.key});

  @override
  ConsumerState<PinSportSetupScreen> createState() =>
      _PinSportSetupScreenState();
}

class _PinSportSetupScreenState extends ConsumerState<PinSportSetupScreen> {
  NaverMapController? _mapController;
  bool _mapReady = false;

  NLatLng _currentLocation = const NLatLng(37.5665, 126.9780); // 기본 서울
  bool _isLocating = false;

  Pin? _selectedPin;
  List<Pin>? _lastPins;

  String _selectedSport = 'GOLF';
  bool _isSubmitting = false;

  static const double _pinLoadRadius = 30.0; // km

  @override
  void initState() {
    super.initState();
    // sportPreferenceProvider의 현재 값을 초기 선택으로 사용
    // build() 이후 ref 접근이 가능하므로 addPostFrameCallback으로 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedSport = ref.read(sportPreferenceProvider);
      // 지원 종목 목록에 있는 경우만 기본값으로 사용
      final isSupported = allSports.any((s) => s.value == savedSport);
      if (isSupported && mounted) {
        setState(() => _selectedSport = savedSport);
      }
      _initLocation();
    });
  }

  Future<void> _initLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await LocationUtils.getCurrentPosition();
      if (pos == null || !mounted) return;

      setState(() {
        _currentLocation = NLatLng(pos.latitude, pos.longitude);
      });
      // 가장 가까운 핀으로 포커스 (핀 데이터가 이미 있으면 즉시, 아니면 나중에)
      _focusNearestPin(pos);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// 현재 위치에서 가장 가까운 핀을 찾아 카메라를 이동시킨다.
  /// 핀 목록이 아직 로드 안 됐으면 현재 위치로만 이동.
  void _focusNearestPin(Position pos) {
    final pinsAsync = ref.read(allPinsProvider);
    final pins = pinsAsync.valueOrNull;
    if (pins == null || pins.isEmpty) {
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: _currentLocation, zoom: 13),
      );
      return;
    }
    final nearest = pins.reduce((a, b) {
      final da = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, a.centerLatitude, a.centerLongitude);
      final db = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, b.centerLatitude, b.centerLongitude);
      return da <= db ? a : b;
    });
    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(nearest.centerLatitude, nearest.centerLongitude),
        zoom: 14,
      ),
    );
  }

  /// 현재 저장된 위치 기준으로 가장 가까운 핀으로 카메라 이동
  void _focusNearestPinFromCurrent(List<Pin> pins) {
    if (pins.isEmpty || _mapController == null) return;
    final lat = _currentLocation.latitude;
    final lng = _currentLocation.longitude;
    final nearest = pins.reduce((a, b) {
      final da = Geolocator.distanceBetween(
          lat, lng, a.centerLatitude, a.centerLongitude);
      final db = Geolocator.distanceBetween(
          lat, lng, b.centerLatitude, b.centerLongitude);
      return da <= db ? a : b;
    });
    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(nearest.centerLatitude, nearest.centerLongitude),
        zoom: 14,
      ),
    );
  }

  void _addPinMarkers(List<Pin> pins) async {
    if (!_mapReady || _mapController == null || !mounted) return;

    final markers = await SportMarkerBuilder.buildMarkers(
      context: context,
      pins: pins,
      selectedPinId: _selectedPin?.id,
      sportType: _selectedSport,
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
    // 마커 색상 갱신을 위해 다시 그림
    if (_lastPins != null) {
      _addPinMarkers(_lastPins!);
    }
  }

  Future<void> _submit() async {
    if (_selectedPin == null) return;

    setState(() => _isSubmitting = true);
    try {
      // 선택한 종목을 선호 종목으로 저장
      await ref.read(sportPreferenceProvider.notifier).select(_selectedSport);

      // 핀 선택 정보는 로컬에 저장 (추후 API 연동 가능)
      // TODO: API 준비 시 primary pin 설정 API 호출

      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '설정에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinsAsync = ref.watch(allPinsProvider);

    // 핀 데이터 도착 시 마커 추가 + 가장 가까운 핀으로 포커스
    ref.listen(
      allPinsProvider,
      (prev, next) {
        next.whenData((pins) {
          if (mounted && _mapReady) {
            _addPinMarkers(pins);
            // 핀이 처음 로드됐고 아직 선택된 핀이 없으면 가장 가까운 핀으로 포커스
            final prevPins = prev?.valueOrNull;
            if ((prevPins == null || prevPins.isEmpty) &&
                pins.isNotEmpty &&
                _selectedPin == null) {
              _focusNearestPinFromCurrent(pins);
            }
          }
        });
      },
    );

    final canSubmit = _selectedPin != null && !_isSubmitting;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('자주 가는 핀 설정'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // ── 진행 표시 (4단계이므로 모두 채움) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(
                    4,
                    (i) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '4단계: 핀 & 종목 설정',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Text(
                      '3 / 3',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '자주 가는 핀을 선택하세요',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '지도에서 핀을 탭하면 선택됩니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── 지도 영역 ──
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: NaverMap(
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
                ),

                // 로딩 인디케이터 (핀 불러오는 중)
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

                // 현재 위치 버튼
                Positioned(
                  top: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'pin_setup_location_btn',
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

          // ── 하단 패널 ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 선택된 핀 표시
                _SelectedPinBadge(pin: _selectedPin),

                const SizedBox(height: 16),

                // 종목 선택
                const Text(
                  '종목 선택',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                _SportChipRow(
                  sports: allSports,
                  selectedSport: _selectedSport,
                  onSportSelected: (sport) =>
                      setState(() => _selectedSport = sport),
                ),

                const SizedBox(height: 16),

                // 시작하기 버튼
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canSubmit
                          ? AppTheme.primaryColor
                          : AppTheme.textDisabled,
                      disabledBackgroundColor: const Color(0xFF333333),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '시작하기',
                            style: TextStyle(fontSize: 16),
                          ),
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

/// 선택된 핀 이름 표시 배지
class _SelectedPinBadge extends StatelessWidget {
  final Pin? pin;

  const _SelectedPinBadge({required this.pin});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: pin != null
            ? AppTheme.primaryColor.withOpacity(0.15)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pin != null
              ? AppTheme.primaryColor.withOpacity(0.4)
              : const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            pin != null
                ? Icons.location_on_rounded
                : Icons.location_off_rounded,
            size: 18,
            color: pin != null ? AppTheme.primaryColor : AppTheme.textDisabled,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pin != null ? pin!.name : '지도에서 핀을 선택해주세요',
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    pin != null ? FontWeight.w600 : FontWeight.w400,
                color: pin != null
                    ? AppTheme.textPrimary
                    : AppTheme.textDisabled,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pin != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 11, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    '선택됨',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

/// 종목 선택 칩 행
class _SportChipRow extends StatelessWidget {
  final List<SportItem> sports;
  final String selectedSport;
  final ValueChanged<String> onSportSelected;

  const _SportChipRow({
    required this.sports,
    required this.selectedSport,
    required this.onSportSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sports.map((sport) {
          final isSelected = selectedSport == sport.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSportSelected(sport.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : const Color(0xFF2A2A2A),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                AppTheme.primaryColor.withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      sport.icon,
                      size: 16,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sport.label,
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
            ),
          );
        }).toList(),
      ),
    );
  }
}
