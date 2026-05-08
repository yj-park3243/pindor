import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game.dart';
import '../repositories/game_repository.dart';

/// 경기 상세 프로바이더
final gameDetailProvider =
    FutureProvider.autoDispose.family<Game, String>((ref, gameId) async {
  final repo = ref.read(gameRepositoryProvider);
  return repo.getGameDetail(gameId);
});

/// 경기 결과 Notifier
class GameResultNotifier extends AutoDisposeFamilyAsyncNotifier<Game, String> {
  @override
  Future<Game> build(String gameId) async {
    final repo = ref.read(gameRepositoryProvider);
    return repo.getGameDetail(gameId);
  }

  /// 결과 입력
  Future<void> submitResult({
    required String myResult,
    required String winnerId,
    int? mannerScore,
  }) async {
    final repo = ref.read(gameRepositoryProvider);
    await repo.submitGameResult(
      arg,
      myResult: myResult,
      winnerId: winnerId,
      mannerScore: mannerScore,
    );
    // 결과 제출 후 재조회
    state = AsyncData(await repo.getGameDetail(arg));
  }

  /// 결과 인증 동의/거절
  Future<ScoreChangeResult?> confirmResult({
    required bool isConfirmed,
    String? comment,
  }) async {
    final repo = ref.read(gameRepositoryProvider);
    final result = await repo.confirmResult(
      arg,
      isConfirmed: isConfirmed,
      comment: comment,
    );
    state = AsyncData(await repo.getGameDetail(arg));
    return result;
  }

  /// 결과 이의 신청
  Future<void> submitDispute({
    required String reason,
    List<String> evidenceImageUrls = const [],
  }) async {
    final repo = ref.read(gameRepositoryProvider);
    await repo.submitDispute(
      arg,
      reason: reason,
      evidenceImageUrls: evidenceImageUrls,
    );
    state = AsyncData(await repo.getGameDetail(arg));
  }
}

final gameResultProvider = AsyncNotifierProvider.autoDispose
    .family<GameResultNotifier, Game, String>(
  GameResultNotifier.new,
);
