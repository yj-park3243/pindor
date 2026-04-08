import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

/// 파일 업로드 레포지토리
/// S3 Presigned URL 방식 지원
class UploadRepository {
  final ApiClient _api;

  const UploadRepository(this._api);

  /// S3 Presigned URL 발급
  Future<PresignedUrlResult> getPresignedUrl({
    required String fileType, // PROFILE_IMAGE | GAME_RESULT | POST_IMAGE | CHAT_IMAGE
    required String contentType,
    required int fileSize,
  }) async {
    final response = await _api.post(
      '/uploads/presigned-url',
      body: {
        'fileType': fileType,
        'contentType': contentType,
        'fileSize': fileSize,
      },
    );
    return PresignedUrlResult.fromJson(
        response['data'] as Map<String, dynamic>);
  }

  /// Presigned URL로 S3에 직접 업로드
  Future<String> uploadToS3({
    required String presignedUrl,
    required String filePath,
    required String contentType,
    void Function(int, int)? onProgress,
  }) async {
    final file = File(filePath);
    final fileBytes = await file.readAsBytes();

    final uploadDio = Dio();
    await uploadDio.put(
      presignedUrl,
      data: fileBytes,
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileBytes.length,
        },
      ),
      onSendProgress: onProgress,
    );

    return presignedUrl.split('?')[0]; // 순수 파일 URL 반환
  }

  /// 파일 확장자 기반 content-type 결정
  String _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// 프로필 이미지 업로드 편의 메서드
  Future<String> uploadProfileImage(String filePath) async {
    final file = File(filePath);
    final size = await file.length();
    final ct = _contentType(filePath);

    final presignedResult = await getPresignedUrl(
      fileType: 'PROFILE_IMAGE',
      contentType: ct,
      fileSize: size,
    );

    return uploadToS3(
      presignedUrl: presignedResult.uploadUrl,
      filePath: filePath,
      contentType: ct,
    );
  }

  /// 게시글 이미지 업로드 편의 메서드
  Future<String> uploadPostImage(String filePath) async {
    final file = File(filePath);
    final size = await file.length();
    final ct = _contentType(filePath);

    final presignedResult = await getPresignedUrl(
      fileType: 'POST_IMAGE',
      contentType: ct,
      fileSize: size,
    );

    return uploadToS3(
      presignedUrl: presignedResult.uploadUrl,
      filePath: filePath,
      contentType: ct,
    );
  }

  /// 경기 증빙 사진 업로드
  Future<List<String>> uploadGameProofs(List<String> filePaths) async {
    final futures = filePaths.map((path) async {
      final file = File(path);
      final size = await file.length();
      final ct = _contentType(path);

      final presignedResult = await getPresignedUrl(
        fileType: 'GAME_RESULT',
        contentType: ct,
        fileSize: size,
      );

      return uploadToS3(
        presignedUrl: presignedResult.uploadUrl,
        filePath: path,
        contentType: ct,
      );
    });

    return Future.wait(futures);
  }
}

class PresignedUrlResult {
  final String uploadUrl;
  final String fileUrl;
  final int expiresIn;

  const PresignedUrlResult({
    required this.uploadUrl,
    required this.fileUrl,
    required this.expiresIn,
  });

  factory PresignedUrlResult.fromJson(Map<String, dynamic> json) {
    return PresignedUrlResult(
      uploadUrl: json['uploadUrl'] as String,
      fileUrl: json['fileUrl'] as String,
      expiresIn: json['expiresIn'] as int? ?? 300,
    );
  }
}

final uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  return UploadRepository(ApiClient.instance);
});
