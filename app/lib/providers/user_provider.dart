import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../repositories/user_repository.dart';
import '../providers/auth_provider.dart';

/// 현재 로그인한 사용자의 전체 User 객체 (SWR 패턴)
///
/// 1. 로컬 DB에서 즉시 로드
/// 2. 백그라운드로 API 갱신 → DB 업데이트 → 자동 반영
class UserNotifier extends AutoDisposeAsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final authState = ref.watch(authStateProvider).valueOrNull;
    if (authState == null || !authState.isAuthenticated) return null;

    final userId = authState.user?.id;
    if (userId == null) return null;

    final repo = ref.read(userRepositoryProvider);

    // 1) 로컬 DB에서 먼저 조회
    final localUser = await repo.getMeLocal(userId);

    // 2) 백그라운드로 API 갱신 (TTL 만료 시만)
    unawaited(repo.refreshMeIfStale(userId).then((_) {
      // 갱신 후 로컬 DB에서 다시 읽어 state 업데이트
      repo.getMeLocal(userId).then((updated) {
        if (updated != null && state.hasValue) {
          state = AsyncData(updated);
        }
      });
    }).catchError((e) {
      debugPrint('[UserProvider] background refresh failed: $e');
    }));

    // 로컬에 있으면 즉시 반환, 없으면 API 호출
    if (localUser != null) return localUser;

    try {
      return await repo.getMe();
    } catch (e) {
      debugPrint('[UserProvider] getMe failed: $e');
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard<User?>(
      () => ref.read(userRepositoryProvider).getMe(),
    );
  }

  Future<void> updateProfile({
    String? nickname,
    String? profileImageUrl,
  }) async {
    final updated = await ref.read(userRepositoryProvider).updateProfile(
          nickname: nickname,
          profileImageUrl: profileImageUrl,
        );
    // DB에 이미 저장됨 (repository에서 처리), state만 즉시 반영
    state = AsyncData(updated);
  }
}

final userNotifierProvider =
    AutoDisposeAsyncNotifierProvider<UserNotifier, User?>(UserNotifier.new);

/// 타 사용자 공개 프로필 조회 (캐시됨)
final userProfileProvider =
    FutureProvider.autoDispose.family<UserProfile, String>((ref, userId) {
  return ref.read(userRepositoryProvider).getUserProfile(userId);
});
