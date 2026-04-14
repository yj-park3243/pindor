import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../core/utils/location_utils.dart';

/// 위치 선택 화면
/// - 네이버 지도 전체화면
/// - 지도 중앙 고정 핀 마커
/// - 카메라 이동 시 중심 좌표로 위치 결정
/// - "이 위치 전송" 버튼 → {latitude, longitude, address} Map을 pop으로 반환
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  NaverMapController? _mapController;
  NLatLng _selectedLocation = const NLatLng(37.5665, 126.9780); // 서울 기본값
  String _address = '';
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _geocodeTimer;

  @override
  void initState() {
    super.initState();
    _initCurrentLocation();
  }

  Future<void> _initCurrentLocation() async {
    try {
      final pos = await LocationUtils.getCurrentPosition(
        timeout: const Duration(seconds: 8),
      );
      if (pos == null || !mounted) return;

      setState(() {
        _selectedLocation = NLatLng(pos.latitude, pos.longitude);
      });
      _reverseGeocode(_selectedLocation);

      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: _selectedLocation,
          zoom: 15,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reverseGeocode(NLatLng loc) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        loc.latitude, loc.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        // 한국 주소 조합: 시/도 + 구/군 + 동/읍/면 + 번지
        final parts = <String>[
          if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
          if (p.subLocality?.isNotEmpty == true) p.subLocality!,
          if (p.thoroughfare?.isNotEmpty == true) p.thoroughfare!,
          if (p.subThoroughfare?.isNotEmpty == true) p.subThoroughfare!,
        ];
        setState(() {
          _address = parts.isNotEmpty ? parts.join(' ') : '주소를 찾을 수 없습니다';
        });
      }
    } catch (e) {
      debugPrint('[LocationPicker] reverse geocoding 실패: $e');
      if (mounted) {
        setState(() => _address = '주소를 찾을 수 없습니다');
      }
    }
  }

  void _onSend() {
    setState(() => _isSending = true);
    Navigator.of(context).pop({
      'latitude': _selectedLocation.latitude,
      'longitude': _selectedLocation.longitude,
      'address': _address.isNotEmpty ? _address : '위치 공유',
    });
  }

  @override
  void dispose() {
    _geocodeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // 네이버 지도 전체화면
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _selectedLocation,
                zoom: 15,
              ),
              mapType: NMapType.navi,
              nightModeEnable: true,
              locationButtonEnable: false,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              LocationUtils.hasPermission().then((granted) {
                if (granted && mounted) {
                  try {
                    controller.setLocationTrackingMode(NLocationTrackingMode.noFollow);
                  } catch (e) {
                    debugPrint('[LocationPicker] 위치 트래킹 설정 실패: $e');
                  }
                }
              });
              // 현재 위치 로딩 완료 후 카메라 이동
              if (!_isLoading) {
                controller.updateCamera(
                  NCameraUpdate.scrollAndZoomTo(
                    target: _selectedLocation,
                    zoom: 15,
                  ),
                );
              }
            },
            onCameraIdle: () async {
              final pos = await _mapController?.getCameraPosition();
              if (pos != null && mounted) {
                setState(() => _selectedLocation = pos.target);
                // 디바운스: 카메라 멈추고 300ms 후 주소 조회
                _geocodeTimer?.cancel();
                _geocodeTimer = Timer(const Duration(milliseconds: 300), () {
                  _reverseGeocode(pos.target);
                });
              }
            },
          ),

          // 상단 앱바
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E1E).withOpacity(0.85),
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '위치 선택',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 중앙 고정 핀 (지도가 움직여도 항상 화면 중앙에 고정)
          const Center(
            child: _CenterPin(),
          ),

          // 로딩 인디케이터
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),

          // 하단 좌표 표시 + 전송 버튼
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 드래그 핸들
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 선택된 좌표 표시
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '선택한 위치',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _address.isNotEmpty ? _address : '주소를 불러오는 중...',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 전송 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _onSend,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppTheme.primaryColor.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  '이 위치 전송',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 지도 중앙 고정 핀 위젯
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 핀 아이콘
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.location_on_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        // 핀 꼬리
        Container(
          width: 2,
          height: 12,
          color: AppTheme.primaryColor,
        ),
        // 그림자 원
        Container(
          width: 8,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}
