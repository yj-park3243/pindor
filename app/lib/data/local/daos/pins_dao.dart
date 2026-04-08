import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/pins_table.dart';
import '../../../models/pin.dart' as model;

part 'pins_dao.g.dart';

@DriftAccessor(tables: [Pins])
class PinsDao extends DatabaseAccessor<AppDatabase> with _$PinsDaoMixin {
  PinsDao(super.db);

  /// 전체 핀 목록 Stream (이름순)
  Stream<List<model.Pin>> watchAllPins() {
    return (select(db.pins)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map(_rowToPin).toList());
  }

  /// 전체 핀 목록 1회 조회
  Future<List<model.Pin>> getAllPins() async {
    final rows = await (select(db.pins)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map(_rowToPin).toList();
  }

  /// 핀 개수 조회 (캐시 유무 확인용)
  Future<int> getPinCount() async {
    final count = countAll();
    final query = selectOnly(db.pins)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 핀 배치 upsert (API 전체 응답 저장)
  Future<void> upsertAllPins(List<model.Pin> pins) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        db.pins,
        pins.map((p) => PinsCompanion(
          id: Value(p.id),
          name: Value(p.name),
          slug: Value(p.slug),
          centerLatitude: Value(p.centerLatitude),
          centerLongitude: Value(p.centerLongitude),
          level: Value(p.level),
          parentPinId: Value(p.parentPinId),
          isActive: Value(p.isActive),
          userCount: Value(p.userCount),
          activeMatchRequests: Value(p.activeMatchRequests),
          createdAt: Value(p.createdAt),
          cachedAt: Value(DateTime.now()),
        )).toList(),
      );
    });
  }

  /// 특정 핀 upsert
  Future<void> upsertPin(model.Pin pin) async {
    await into(db.pins).insertOnConflictUpdate(
      PinsCompanion(
        id: Value(pin.id),
        name: Value(pin.name),
        slug: Value(pin.slug),
        centerLatitude: Value(pin.centerLatitude),
        centerLongitude: Value(pin.centerLongitude),
        level: Value(pin.level),
        parentPinId: Value(pin.parentPinId),
        isActive: Value(pin.isActive),
        userCount: Value(pin.userCount),
        activeMatchRequests: Value(pin.activeMatchRequests),
        createdAt: Value(pin.createdAt),
        cachedAt: Value(DateTime.now()),
      ),
    );
  }

  /// drift row → Pin 모델 변환
  model.Pin _rowToPin(Pin row) {
    return model.Pin(
      id: row.id,
      name: row.name,
      slug: row.slug,
      centerLatitude: row.centerLatitude,
      centerLongitude: row.centerLongitude,
      level: row.level,
      parentPinId: row.parentPinId,
      isActive: row.isActive,
      userCount: row.userCount,
      activeMatchRequests: row.activeMatchRequests,
      createdAt: row.createdAt,
    );
  }
}
