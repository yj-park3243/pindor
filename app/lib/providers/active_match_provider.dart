import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match.dart';
import '../repositories/matching_repository.dart';

/// 활성 매칭 프로바이더
/// - GET /matches/active 호출
/// - PENDING_ACCEPT / CHAT / CONFIRMED 상태의 매칭이 있으면 반환, 없으면 null
/// - 앱 시작 시 화면 잠금 여부 판단에 사용
final activeMatchProvider = FutureProvider.autoDispose<Match?>((ref) async {
  final repo = ref.read(matchingRepositoryProvider);
  return repo.getActiveMatch();
});
