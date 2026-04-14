import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../repositories/user_repository.dart';
import '../providers/auth_provider.dart';
import '../providers/sport_preference_provider.dart';

/// 현재 로그인한 사용자의 전체 User 객체 (SWR 패턴)
///
/// 1. 로컬 DB에서 즉시 로드
/// 2. 백그라운드로 API 갱신 → DB 업데이트 → 자동 반영
class UserNotifier extends AutoDisposeAsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final authState = ref.watch(authStateProvider).valueOrNull;
    if (authState == null || !authState.isAuthenticated) return null;

    // authState.user가 있으면 바로 사용 (로그인 직후)
    if (authState.user != null) {
      // 서버에서 받은 preferredSportType으로 초기화
      unawaited(ref
          .read(sportPreferenceProvider.notifier)
          .initFromServer(authState.user!.preferredSportType));

      // 백그라운드로 최신 데이터 갱신
      final repo = ref.read(userRepositoryProvider);
      unawaited(repo.getMe().then((updated) {
        if (updated != null && state.hasValue) {
          state = AsyncData(updated);
          // 갱신된 데이터로 종목 선호도 재동기화
          unawaited(ref
              .read(sportPreferenceProvider.notifier)
              .initFromServer(updated.preferredSportType));
        }
      }).catchError((e) {
        debugPrint('[UserProvider] background refresh failed: $e');
      }));
      return authState.user;
    }

    // user가 null인 경우 (네트워크 에러로 토큰만 유지된 상태)
    final repo = ref.read(userRepositoryProvider);
    try {
      final user = await repo.getMe();
      if (user != null) {
        unawaited(ref
            .read(sportPreferenceProvider.notifier)
            .initFromServer(user.preferredSportType));
      }
      return user;
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
