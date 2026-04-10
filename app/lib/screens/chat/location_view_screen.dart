import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../../config/theme.dart';
import '../../models/message.dart';

/// 위치 메시지 전체화면 보기
/// - 전달받은 좌표에 마커 표시
/// - AppBar에 주소 표시
/// - 하단 "주소 복사" 버튼
class LocationViewScreen extends StatefulWidget {
  final LocationData locationData;

  const LocationViewScreen({super.key, required this.locationData});

  @override
  State<LocationViewScreen> createState() => _LocationViewScreenState();
}

class _LocationViewScreenState extends State<LocationViewScreen> {
  NaverMapController? _mapController;
  bool _mapReady = false;

  String get _displayAddress {
    final name = widget.locationData.placeName;
    final addr = widget.locationData.address;
    if (name != null && name.isNotEmpty) return name;
    if (addr != null && addr.isNotEmpty) return addr;
    final lat = widget.locationData.latitude.toStringAsFixed(5);
    final lng = widget.locationData.longitude.toStringAsFixed(5);
    return '위도 $lat, 경도 $lng';
  }

  Future<void> _addMarker() async {
    if (!_mapReady || _mapController == null) return;
    final loc = NLatLng(
      widget.locationData.latitude,
      widget.locationData.longitude,
    );
    final marker = NMarker(
      id: 'shared_location',
      position: loc,
      iconTintColor: AppTheme.primaryColor,
    );
    _mapController!.addOverlay(marker);
  }

  void _copyAddress() {
    Clipboard.setData(ClipboardData(text: _displayAddress));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('주소가 복사되었습니다'),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = NLatLng(
      widget.locationData.latitude,
      widget.locationData.longitude,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '공유된 위치',
              style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
            Text(
              _displayAddress,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: Stack(
        children: [
          // 네이버 지도
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: loc,
                zoom: 15,
              ),
              mapType: NMapType.navi,
              nightModeEnable: true,
              locationButtonEnable: false,
              zoomGesturesEnable: true,
              scrollGesturesEnable: true,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              _mapReady = true;
              _addMarker();
            },
          ),

          // 하단 주소 복사 버튼
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

                  // 위치 정보
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.locationData.placeName != null &&
                                widget.locationData.placeName!.isNotEmpty)
                              Text(
                                widget.locationData.placeName!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            Text(
                              widget.locationData.address ??
                                  '위도 ${widget.locationData.latitude.toStringAsFixed(5)}, '
                                  '경도 ${widget.locationData.longitude.toStringAsFixed(5)}',
                              style: TextStyle(
                                fontSize: widget.locationData.placeName != null ? 12 : 14,
                                color: widget.locationData.placeName != null
                                    ? const Color(0xFF9CA3AF)
                                    : Colors.white,
                                fontWeight: widget.locationData.placeName != null
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 주소 복사 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _copyAddress,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text(
                        '주소 복사',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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
