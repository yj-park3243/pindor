import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sports_profile.dart';
import '../repositories/profile_repository.dart';
import '../providers/auth_provider.dart';

/// 내 스포츠 프로필 목록 (생성/수정 후 갱신)
class SportsProfilesNotifier
    extends AutoDisposeAsyncNotifier<List<SportsProfile>> {
  @override
  Future<List<SportsProfile>> build() async {
    final isAuthenticated =
        ref.watch(authStateProvider).valueOrNull?.isAuthenticated ?? false;
    if (!isAuthenticated) return [];
    return ref.read(profileRepositoryProvider).getMySportsProfiles();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).getMySportsProfiles(),
    );
  }

  Future<void> createProfile({
    required String sportType,
    String? displayName,
    String? matchMessage,
    double? gHandicap,
  }) async {
    final profile = await ref.read(profileRepositoryProvider).createSportsProfile(
          sportType: sportType,
          displayName: displayName,
          matchMessage: matchMessage,
          gHandicap: gHandicap,
        );
    final current = state.value ?? [];
    state = AsyncData([...current, profile]);
  }

  Future<void> updateProfile(
    String profileId, {
    String? displayName,
    String? matchMessage,
    double? gHandicap,
  }) async {
    final updated = await ref.read(profileRepositoryProvider).updateSportsProfile(
          profileId,
          displayName: displayName,
          matchMessage: matchMessage,
          gHandicap: gHandicap,
        );
    final current = state.value ?? [];
    state = AsyncData(
      current.map((p) => p.id == profileId ? updated : p).toList(),
    );
  }

  Future<void> deleteProfile(String profileId) async {
    await ref.read(profileRepositoryProvider).deleteSportsProfile(profileId);
    final current = state.value ?? [];
    state = AsyncData(
      current.where((p) => p.id != profileId).toList(),
    );
  }
}

final sportsProfilesProvider = AutoDisposeAsyncNotifierProvider<
    SportsProfilesNotifier, List<SportsProfile>>(SportsProfilesNotifier.new);
