import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/matches_table.dart';
import '../../../models/match.dart' as model;

part 'matches_dao.g.dart';

@DriftAccessor(tables: [Matches])
class MatchesDao extends DatabaseAccessor<AppDatabase> with _$MatchesDaoMixin {
  MatchesDao(super.db);

  /// 매칭 목록 Stream (최신순)
  Stream<List<model.Match>> watchMatches({String? status}) {
    var query = select(db.matches)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (status != null) {
      query = query..where((t) => t.status.equals(status));
    }
    return query.watch().map((rows) => rows.map(_rowToMatch).toList());
  }

  /// 매칭 목록 1회 조회
  Future<List<model.Match>> getMatches({String? status}) async {
    var query = select(db.matches)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (status != null) {
      query = query..where((t) => t.status.equals(status));
    }
    final rows = await query.get();
    return rows.map(_rowToMatch).toList();
  }

  /// 매칭 개수
  Future<int> getMatchCount() async {
    final count = countAll();
    final query = selectOnly(db.matches)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 매칭 단건 조회
  Future<model.Match?> getMatch(String matchId) async {
    final row = await (select(db.matches)
          ..where((t) => t.id.equals(matchId)))
        .getSingleOrNull();
    return row != null ? _rowToMatch(row) : null;
  }

  /// 전체 매칭 삭제 (로컬 캐시 정리)
  Future<void> deleteAllMatches() async {
    await delete(db.matches).go();
  }

  /// 매칭 배치 upsert
  Future<void> upsertMatches(List<model.Match> matches) async {
    if (matches.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(
        db.matches,
        matches.map(_matchToCompanion).toList(),
      );
    });
  }

  /// 매칭 단건 upsert
  Future<void> upsertMatch(model.Match match) async {
    await into(db.matches).insertOnConflictUpdate(_matchToCompanion(match));
  }

  MatchesCompanion _matchToCompanion(model.Match m) {
    return MatchesCompanion(
      id: Value(m.id),
      status: Value(m.status),
      sportType: Value(m.sportType),
      pinId: const Value(null),
      requesterId: Value(m.matchRequestId),
      responderId: Value(m.opponent.id),
      detailJson: Value(jsonEncode(m.toJson())),
      scheduledAt: Value(m.scheduledDate != null && m.scheduledTime != null
          ? DateTime.tryParse('${m.scheduledDate}T${m.scheduledTime}')
          : null),
      createdAt: Value(m.createdAt),
      cachedAt: Value(DateTime.now()),
    );
  }

  model.Match _rowToMatch(Matche row) {
    if (row.detailJson != null) {
      try {
        final json = jsonDecode(row.detailJson!) as Map<String, dynamic>;
        return model.Match.fromJson(json);
      } catch (_) {}
    }
    // fallback — detailJson 없는 경우 (발생하면 안 됨)
    return model.Match(
      id: row.id,
      matchRequestId: row.requesterId,
      sportType: row.sportType,
      opponent: const model.MatchOpponent(
        id: '',
        nickname: '',
        tier: 'IRON',
        sportType: 'GOLF',
        gamesPlayed: 0,
        wins: 0,
        losses: 0,
      ),
      status: row.status,
      chatRoomId: '',
      createdAt: row.createdAt,
    );
  }
}
