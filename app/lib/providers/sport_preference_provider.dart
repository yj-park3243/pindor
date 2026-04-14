import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_client.dart';

/// 유저가 마지막으로 선택한 스포츠를 기억하는 Provider
/// 핀 상세, 게시판 등에서 공유하여 기본값으로 사용
class SportPreferenceNotifier extends Notifier<String> {
  static const _key = 'preferred_sport';

  @override
  String build() {
    _load();
    return 'GOLF'; // 초기 기본값
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      state = saved;
    }
  }

  /// 종목 선택: 로컬 저장 + 서버 동기화
  Future<void> select(String sportType) async {
    state = sportType;
    // 로컬 저장 (오프라인 대응)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, sportType);
    // 서버 저장 (실패해도 로컬은 유지)
    try {
      await ApiClient.instance.patch(
        '/users/me',
        body: {'preferredSportType': sportType},
      );
    } catch (e) {
      debugPrint('[SportPreference] server sync failed: $e');
    }
  }

  /// 로그인 후 서버값으로 초기화 (서버 우선, 없으면 로컬 유지)
  Future<void> initFromServer(String? serverSportType) async {
    if (serverSportType != null && serverSportType.isNotEmpty) {
      state = serverSportType;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, serverSportType);
    }
  }
}

final sportPreferenceProvider =
    NotifierProvider<SportPreferenceNotifier, String>(SportPreferenceNotifier.new);
