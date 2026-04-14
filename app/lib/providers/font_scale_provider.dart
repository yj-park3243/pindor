import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 글자 크기 배율 Provider
/// SharedPreferences에 저장하여 앱 재시작 시에도 유지
class FontScaleNotifier extends Notifier<double> {
  static const _key = 'font_scale';
  static const defaultScale = 1.0;

  static const presets = [
    ('작게', 0.85),
    ('보통', 1.0),
    ('크게', 1.15),
    ('아주 크게', 1.3),
  ];

  @override
  double build() {
    _load();
    return defaultScale;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_key);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> setScale(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, scale);
  }

  String get currentLabel {
    for (final (label, value) in presets) {
      if ((value - state).abs() < 0.01) return label;
    }
    return '보통';
  }
}

final fontScaleProvider =
    NotifierProvider<FontScaleNotifier, double>(FontScaleNotifier.new);
