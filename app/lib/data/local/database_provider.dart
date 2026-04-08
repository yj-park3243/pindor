import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database.dart';
import 'cache_ttl_helper.dart';

/// AppDatabase 싱글톤 Provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// CacheTtlHelper Provider
final cacheTtlHelperProvider = Provider<CacheTtlHelper>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CacheTtlHelper(db);
});
