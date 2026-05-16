/// 개발자 메뉴 "데이터" 탭에 노출되는 마지막 동기화 시각 기록.
/// 각 provider/repository 의 서버 fetch 가 끝날 때 `mark(key)` 호출.
class LastSyncStats {
  LastSyncStats._();
  static final Map<String, DateTime> _data = {};

  static void mark(String key) {
    _data[key] = DateTime.now();
  }

  static DateTime? get(String key) => _data[key];
  static Map<String, DateTime> snapshot() => Map.unmodifiable(_data);
}
