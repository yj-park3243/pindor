import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../../config/theme.dart';
import '../../models/pin.dart';

/// 채팅 말풍선 스타일 핀 마커
/// 네모 사각형 안에 핀 이름, 아래 삼각형 꼬리
class SportPinMarker extends StatelessWidget {
  final String label;
  final bool isSelected;

  const SportPinMarker({
    super.key,
    required this.label,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected ? AppTheme.primaryColor : const Color(0xFF1E1E1E);
    final textColor = isSelected ? Colors.white : AppTheme.textPrimary;
    final borderColor = isSelected ? AppTheme.primaryColor : const Color(0xFF34A853);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 말풍선 사각형
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
              height: 1.2,
            ),
          ),
        ),
        // 삼각형 꼬리
        CustomPaint(
          size: const Size(12, 7),
          painter: _TrianglePainter(
            color: bgColor,
            borderColor: borderColor,
          ),
        ),
      ],
    );
  }
}

/// 삼각형 꼬리 페인터
class _TrianglePainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _TrianglePainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) =>
      color != old.color || borderColor != old.borderColor;
}

/// NMarker 빌더
class SportMarkerBuilder {
  static Future<Set<NMarker>> buildMarkers({
    required BuildContext context,
    required List<Pin> pins,
    String? selectedPinId,
    String? sportType,
    void Function(Pin pin)? onTap,
  }) async {
    final markers = <NMarker>{};

    for (final pin in pins) {
      final isSelected = pin.id == selectedPinId;
      final width = (pin.name.length * 14.0 + 32).clamp(70.0, 220.0);
      const height = 46.0;

      final marker = NMarker(
        id: pin.id,
        position: NLatLng(pin.centerLatitude, pin.centerLongitude),
        icon: await NOverlayImage.fromWidget(
          widget: SizedBox(
            width: width,
            height: height,
            child: SportPinMarker(
              label: pin.name,
              isSelected: isSelected,
            ),
          ),
          size: Size(width, height),
          context: context,
        ),
        anchor: const NPoint(0.5, 1.0),
      );

      if (onTap != null) {
        marker.setOnTapListener((_) => onTap(pin));
      }
      markers.add(marker);
    }

    return markers;
  }
}

/// 근접 핀 필터 (선택적 사용)
List<Pin> filterNearbyPins(List<Pin> pins, {double radiusKm = 2.0}) {
  final sorted = [...pins]..sort((a, b) => b.userCount.compareTo(a.userCount));
  final kept = <Pin>[];

  for (final pin in sorted) {
    final tooClose = kept.any(
      (k) => _haversineKm(
            k.centerLatitude, k.centerLongitude,
            pin.centerLatitude, pin.centerLongitude,
          ) < radiusKm,
    );
    if (!tooClose) kept.add(pin);
  }
  return kept;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
      math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180;
