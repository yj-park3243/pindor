import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';

class BlockedUser {
  final String id;
  final String? nickname;
  final String? profileImageUrl;
  final DateTime blockedAt;

  BlockedUser({required this.id, this.nickname, this.profileImageUrl, required this.blockedAt});

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    id: json['id'] as String,
    nickname: json['nickname'] as String?,
    profileImageUrl: json['profileImageUrl'] as String?,
    blockedAt: DateTime.parse(json['blockedAt'] as String),
  );
}

class BlockRepository {
  final ApiClient _api;
  const BlockRepository(this._api);

  Future<void> blockUser(String userId) async {
    await _api.post('/users/blocks', body: {'blockedUserId': userId});
  }

  Future<void> unblockUser(String userId) async {
    await _api.delete('/users/blocks/$userId');
  }

  Future<List<BlockedUser>> getBlockedUsers() async {
    final response = await _api.get('/users/blocks');
    final data = response['data'] as List<dynamic>;
    return data.map((e) => BlockedUser.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final blockRepositoryProvider = Provider<BlockRepository>((ref) {
  return BlockRepository(ApiClient.instance);
});

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((ref) {
  return ref.read(blockRepositoryProvider).getBlockedUsers();
});
