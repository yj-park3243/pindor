import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../models/game.dart';

class GameRepository {
  final ApiClient _api;

  const GameRepository(this._api);

  Future<Game> getGameDetail(String gameId) async {
    final response = await _api.get('/games/$gameId');
    return Game.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 결과 증빙 사진 업로드
  /// NOTE: 서버에 /games/:gameId/proofs 라우트가 없음
  /// S3 presigned URL을 사용하여 업로드 후, 결과 입력 시 imageUrl을 포함하는 방식 권장
  Future<void> uploadProofs(String gameId, List<String> imagePaths) async {
    final formData = FormData();
    for (final path in imagePaths) {
      formData.files.add(
        MapEntry(
          'images',
          await MultipartFile.fromFile(path, filename: path.split('/').last),
        ),
      );
    }
    formData.fields.add(const MapEntry('imageType', 'SCORECARD'));

    await _api.uploadMultipart('/games/$gameId/proofs', formData);
  }

  /// 경기 결과 입력
  /// [myResult]: 'WIN' | 'DRAW' | 'LOSS'
  /// [winnerId]: 무승부면 빈 문자열, 아니면 승자 프로필 ID
  /// [mannerScore]: 선택적 매너 점수 (1~5)
  Future<void> submitGameResult(
    String gameId, {
    required String myResult,
    required String winnerId,
    int? mannerScore,
  }) async {
    await _api.post(
      '/games/$gameId/result',
      body: {
        'myResult': myResult,
        'winnerId': winnerId,
        if (mannerScore != null) 'mannerScore': mannerScore,
      },
    );
  }

  /// 결과 인증 동의/거절
  Future<ScoreChangeResult?> confirmResult(
    String gameId, {
    required bool isConfirmed,
    String? comment,
  }) async {
    final response = await _api.post(
      '/games/$gameId/confirm',
      body: {
        'isConfirmed': isConfirmed,
        if (comment != null) 'comment': comment,
      },
    );
    final data = response['data'] as Map<String, dynamic>?;
    if (data != null && data['scoreChange'] != null) {
      return ScoreChangeResult.fromJson(
          data['scoreChange'] as Map<String, dynamic>);
    }
    return null;
  }

  /// 증빙 이미지 URL을 서버에 연결 (이미 S3에 업로드된 URL)
  /// NOTE: 서버에 POST /games/:gameId/proofs 라우트가 없음 — 서버 추가 필요
  Future<void> uploadProofUrls(String gameId, List<String> imageUrls) async {
    await _api.post(
      '/games/$gameId/proofs',
      body: {
        'imageUrls': imageUrls,
      },
    );
  }

  /// 이의 신청
  Future<void> submitDispute(
    String gameId, {
    required String reason,
    List<String> evidenceImageUrls = const [],
  }) async {
    await _api.post(
      '/games/$gameId/dispute',
      body: {
        'reason': reason,
        'evidenceImageUrls': evidenceImageUrls,
      },
    );
  }
}

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository(ApiClient.instance);
});
