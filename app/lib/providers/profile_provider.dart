import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sports_profile.dart';
import '../repositories/profile_repository.dart';
import '../providers/auth_provider.dart';

/// 내 스포츠 프로필 목록 (생성/수정 후 갱신)
class SportsProfilesNotifier
    extends AutoDisposeAsyncNotifier<List<SportsProfile>> {
  static const _orderKey = 'sport_profile_order';

  @override
  Future<List<SportsProfile>> build() async {
    final isAuthenticated =
        ref.watch(authStateProvider).valueOrNull?.isAuthenticated ?? false;
    if (!isAuthenticated) return [];
    final profiles =
        await ref.read(profileRepositoryProvider).getMySportsProfiles();
    return _applyLocalOrder(profiles);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final profiles =
          await ref.read(profileRepositoryProvider).getMySportsProfiles();
      return _applyLocalOrder(profiles);
    });
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
    final next = [...current, profile];
    await _saveOrder(next.map((p) => p.sportType).toList());
    state = AsyncData(next);
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
    final next = current.where((p) => p.id != profileId).toList();
    await _saveOrder(next.map((p) => p.sportType).toList());
    state = AsyncData(next);
  }

  /// index 카드를 한 칸 위로 이동
  Future<void> moveUp(int index) async {
    final current = state.value ?? [];
    if (index <= 0 || index >= current.length) return;
    final next = [...current];
    final tmp = next[index - 1];
    next[index - 1] = next[index];
    next[index] = tmp;
    await _saveOrder(next.map((p) => p.sportType).toList());
    state = AsyncData(next);
  }

  /// index 카드를 한 칸 아래로 이동
  Future<void> moveDown(int index) async {
    final current = state.value ?? [];
    if (index < 0 || index >= current.length - 1) return;
    final next = [...current];
    final tmp = next[index + 1];
    next[index + 1] = next[index];
    next[index] = tmp;
    await _saveOrder(next.map((p) => p.sportType).toList());
    state = AsyncData(next);
  }

  /// 로컬에 저장된 sport_type 순서대로 정렬. 저장된 순서에 없는 종목은 뒤에 붙인다.
  Future<List<SportsProfile>> _applyLocalOrder(
      List<SportsProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final order = prefs.getStringList(_orderKey);
    if (order == null || order.isEmpty) return profiles;

    final indexOf = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };
    final sorted = [...profiles];
    sorted.sort((a, b) {
      final ai = indexOf[a.sportType] ?? order.length;
      final bi = indexOf[b.sportType] ?? order.length;
      return ai.compareTo(bi);
    });
    return sorted;
  }

  Future<void> _saveOrder(List<String> sportTypes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, sportTypes);
  }
}

final sportsProfilesProvider = AutoDisposeAsyncNotifierProvider<
    SportsProfilesNotifier, List<SportsProfile>>(SportsProfilesNotifier.new);
