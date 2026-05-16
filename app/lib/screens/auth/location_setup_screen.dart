import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/location_utils.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pin_provider.dart';
import '../../widgets/map/sport_marker.dart';
import '../profile/profile_screen.dart' show selectedPinProvider;
// Pin 모델 자체에 centerLatitude/Longitude 필드 사용
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';

/// 3단계: 자주 가는 핀 선택 화면
class LocationSetupScreen extends ConsumerStatefulWidget {
  const LocationSetupScreen({super.key});

  @override
  ConsumerState<LocationSetupScreen> createState() =>
      _LocationSetupScreenState();
}

class _LocationSetupScreenState extends ConsumerState<LocationSetupScreen> {
  NaverMapController? _mapController;
  bool _mapReady = false;

  // 기본 fallback: 서울역 (위치 권한 거부 또는 GPS 미가용 시)
  static const _seoulStation = NLatLng(37.5547, 126.9707);
  NLatLng _currentLocation = _seoulStation;
  Position? _lastPosition;
  bool _didAutoFocus = false;

  Pin? _selectedPin;
  List<Pin>? _lastPins;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    final pos = await LocationUtils.getCurrentPosition();
    if (!mounted) return;

    if (pos != null) {
      _lastPosition = pos;
      setState(() {
        _currentLocation = NLatLng(pos.latitude, pos.longitude);
      });
    } else {
      // 위치 권한 거부/실패 → 서울역 기준으로 fallback Position 생성
      _lastPosition = Position(
        latitude: _seoulStation.latitude,
        longitude: _seoulStation.longitude,
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
    _maybeFocusNearestPin();
  }

  /// 위치·지도·핀 3개 중 가장 늦게 준비된 시점에 가장 가까운 핀으로 카메라 이동.
  /// 한 번 자동 포커스된 이후에는 사용자 제스처를 존중해 재호출하지 않음.
  /// 단, 핀 목록이 아직 비어있다면 _didAutoFocus를 set하지 않고 다음 호출에서 재시도.
  void _maybeFocusNearestPin({bool force = false}) {
    if (!force && _didAutoFocus) return;
    final pos = _lastPosition;
    if (pos == null || !_mapReady || _mapController == null) return;

    final pins = ref.read(allPinsProvider).valueOrNull;
    if (pins == null || pins.isEmpty) {
      // 핀 데이터 미도착 — 카메라/플래그 모두 손대지 않음.
      // ref.listen(allPinsProvider)에서 데이터 도착 시 다시 호출됨.
      return;
    }
    final nearest = pins.reduce((a, b) {
      final da = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, a.centerLatitude, a.centerLongitude);
      final db = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, b.centerLatitude, b.centerLongitude);
      return da <= db ? a : b;
    });
    _mapController!.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(nearest.centerLatitude, nearest.centerLongitude),
        zoom: 14,
      ),
    );
    _didAutoFocus = true;
  }

  void _addPinMarkers(List<Pin> pins) async {
    if (!_mapReady || _mapController == null || !mounted) return;

    final markers = await SportMarkerBuilder.buildMarkers(
      context: context,
      pins: pins,
      selectedPinId: _selectedPin?.id,
      sportType: null,
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
    if (_lastPins != null) {
      _addPinMarkers(_lastPins!);
    }
  }

  Future<void> _submit() async {
    if (_selectedPin == null) return;

    setState(() => _isSubmitting = true);
    try {
      // 선택한 핀을 SharedPreferences에 저장
      await ref.read(selectedPinProvider.notifier).select(_selectedPin);

      // 유저 정보 새로 고침 (sportsProfiles 포함)
      await ref.read(authStateProvider.notifier).refreshUser();

      // 회원가입 4단계 전체 완료 → isNewUser=false로 강제
      ref.read(authStateProvider.notifier).completeSetup();

      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '위치 설정에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinsAsync = ref.watch(allPinsProvider);

    ref.listen(
      allPinsProvider,
      (_, next) {
        next.whenData((pins) {
          if (mounted && _mapReady) {
            _addPinMarkers(pins);
            _maybeFocusNearestPin();
          }
        });
      },
    );

    final canSubmit = _selectedPin != null && !_isSubmitting;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('핀 선택'),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 진행 표시 바 (4/4)
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
                      '4단계: 핀 선택',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Text(
                      '4 / 4',
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

          // 지도
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: Builder(builder: (context) {
                    final favoritePin = ref.read(selectedPinProvider);
                    final initialTarget = favoritePin != null
                        ? NLatLng(favoritePin.centerLatitude, favoritePin.centerLongitude)
                        : _currentLocation;
                    final initialZoom = favoritePin != null ? 14.0 : 12.0;
                    return NaverMap(
                    options: NaverMapViewOptions(
                      initialCameraPosition: NCameraPosition(
                        target: initialTarget,
                        zoom: initialZoom,
                      ),
                      mapType: NMapType.basic,
                      locationButtonEnable: true,
                      rotationGesturesEnable: false,
                    ),
                    onMapReady: (controller) async {
                      _mapController = controller;
                      _mapReady = true;
                      // 1) 내 위치 점 표시 (트래킹 모드 먼저 설정해야 카메라가 핀으로 고정됨)
                      try {
                        if (await LocationUtils.hasPermission() && mounted) {
                          controller.setLocationTrackingMode(NLocationTrackingMode.noFollow);
                        }
                      } catch (e) {
                        debugPrint('[LocationSetup] 위치 트래킹 설정 실패: $e');
                      }
                      // 2) 마커 추가
                      final pins = pinsAsync.valueOrNull;
                      if (pins != null && pins.isNotEmpty) {
                        _addPinMarkers(pins);
                      }
                      // 3) 카메라를 핀에 강제 이동 (트래킹 모드가 카메라를 옮겼을 수 있으므로 마지막에)
                      if (!mounted) return;
                      if (favoritePin != null) {
                        controller.updateCamera(NCameraUpdate.scrollAndZoomTo(
                          target: NLatLng(favoritePin.centerLatitude, favoritePin.centerLongitude),
                          zoom: 14,
                        ));
                        _didAutoFocus = true;
                      } else {
                        _maybeFocusNearestPin();
                      }
                    },
                    );
                  }),
                ),

                // 로딩 인디케이터
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
                            color: Colors.black.withValues(alpha: 0.08),
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
              ],
            ),
          ),

          // 하단 패널
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
              mainAxisSize: MainAxisSize.min,
              children: [
                // 선택된 핀 표시
                _SelectedPinBadge(pin: _selectedPin),

                const SizedBox(height: 16),

                // 시작하기 버튼
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
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
            ? AppTheme.primaryColor.withValues(alpha: 0.06)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pin != null
              ? AppTheme.primaryColor.withValues(alpha: 0.4)
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
                fontWeight: pin != null ? FontWeight.w600 : FontWeight.w400,
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
