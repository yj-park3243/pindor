import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

/// KCP 본인인증 Repository
class KcpRepository {
  final ApiClient _api;

  KcpRepository(this._api);

  /// KCP 인증 HTML Form 조회
  /// GET /v1/auth/kcp/form
  Future<String> getForm({String? returnUrl}) async {
    final queryParams = returnUrl != null ? '?returnUrl=${Uri.encodeComponent(returnUrl)}' : '';
    final response = await _api.get('/auth/kcp/form$queryParams');
    final data = response['data'] as Map<String, dynamic>;
    return data['html'] as String;
  }

  /// KCP 인증 결과 검증
  /// POST /v1/auth/kcp/verify
  Future<Map<String, dynamic>> verify(String key) async {
    final response = await _api.post(
      '/auth/kcp/verify',
      body: {'key': key},
    );
    return response['data'] as Map<String, dynamic>;
  }
}

final kcpRepositoryProvider = Provider<KcpRepository>((ref) {
  return KcpRepository(ApiClient.instance);
});
