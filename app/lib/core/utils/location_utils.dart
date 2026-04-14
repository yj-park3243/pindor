import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// 위치 조회 결과 (null이면 실패)
typedef LocationResult = Position?;

/// 위치 서비스 유틸리티
///
/// Geolocator / NaverMap 위치 에러를 일괄 방어:
/// - PlatformException(LOCATION_ERROR, kCLErrorDomain ...) — iOS 위치 서비스 비활성
/// - TimeoutException — GPS 응답 지연
/// - LocationServiceDisabledException — 위치 서비스 꺼짐
/// - PermissionDeniedException — 위치 권한 거부
class LocationUtils {
  LocationUtils._();

  /// 서울 시청 좌표 (기본값)
  static const double defaultLat = 37.5665;
  static const double defaultLng = 126.9780;

  /// 위치 권한이 허용 상태인지 확인 (요청 없이 현재 상태만 체크)
  static Future<bool> hasPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// 위치 권한 요청 후 허용 여부 반환
  static Future<bool> requestPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 안전하게 현재 위치를 가져옵니다.
  ///
  /// 모든 플랫폼 예외, 타임아웃, 권한 에러를 내부에서 처리하고
  /// 실패 시 null을 반환합니다.
  static Future<LocationResult> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout,
      );
    } on TimeoutException {
      debugPrint('[Location] 위치 조회 타임아웃 (${timeout.inSeconds}s)');
      return null;
    } on PlatformException catch (e) {
      debugPrint('[Location] 플랫폼 에러: ${e.code} ${e.message}');
      return null;
    } on LocationServiceDisabledException {
      debugPrint('[Location] 위치 서비스 비활성');
      return null;
    } catch (e) {
      debugPrint('[Location] 위치 조회 실패: $e');
      return null;
    }
  }
}
