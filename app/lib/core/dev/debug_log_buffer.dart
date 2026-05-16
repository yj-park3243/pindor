import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 개발자 메뉴 → "로그" 탭에 표시되는 in-memory ring buffer.
/// - `attach()` 한 번 호출 → `debugPrint` 출력이 자동으로 캡처됨.
/// - 기본 500개까지 유지 (메모리 부담 방지). 오래된 것부터 폐기.
/// - 변경 시 `entries` 스트림으로 notify (UI 자동 갱신).
class DebugLogBuffer {
  DebugLogBuffer._();
  static final DebugLogBuffer instance = DebugLogBuffer._();

  static const int _maxEntries = 500;
  final Queue<DebugLogEntry> _buffer = Queue();
  final StreamController<List<DebugLogEntry>> _ctrl =
      StreamController.broadcast();
  bool _attached = false;
  DebugPrintCallback? _original;

  Stream<List<DebugLogEntry>> get stream => _ctrl.stream;
  List<DebugLogEntry> get snapshot => List.unmodifiable(_buffer);

  /// `debugPrint` 를 가로채 ring buffer 에 적재. main() 진입 시 한 번 호출.
  void attach() {
    if (_attached) return;
    _attached = true;
    _original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) _append(message);
      _original?.call(message, wrapWidth: wrapWidth);
    };
  }

  void _append(String message) {
    _buffer.addLast(DebugLogEntry(time: DateTime.now(), message: message));
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
    if (!_ctrl.isClosed) _ctrl.add(List.unmodifiable(_buffer));
  }

  void clear() {
    _buffer.clear();
    if (!_ctrl.isClosed) _ctrl.add(const []);
  }
}

class DebugLogEntry {
  final DateTime time;
  final String message;
  const DebugLogEntry({required this.time, required this.message});
}
