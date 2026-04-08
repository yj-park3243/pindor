import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> select(String sportType) async {
    state = sportType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, sportType);
  }
}

final sportPreferenceProvider =
    NotifierProvider<SportPreferenceNotifier, String>(SportPreferenceNotifier.new);
