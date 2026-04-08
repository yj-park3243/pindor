import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match_request.dart';
import '../models/match.dart';
import '../repositories/matching_repository.dart';

/// 매칭 요청 목록 상태
class MatchRequestListState {
  final List<MatchRequest> sent;
  final List<MatchRequest> received;
  final bool isLoading;
  final String? error;

  const MatchRequestListState({
    this.sent = const [],
    this.received = const [],
    this.isLoading = false,
    this.error,
  });

  MatchRequestListState copyWith({
    List<MatchRequest>? sent,
    List<MatchRequest>? received,
    bool? isLoading,
    String? error,
  }) {
    return MatchRequestListState(
      sent: sent ?? this.sent,
      received: received ?? this.received,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 매칭 목록 프로바이더 (SWR 패턴)
final matchListProvider = FutureProvider.autoDispose
    .family<List<Match>, String?>((ref, status) async {
  final repo = ref.read(matchingRepositoryProvider);

  final hasCache = await repo.hasMatchesCache();
  if (hasCache) {
    unawaited(repo.refreshIfStale().catchError((e) {
      debugPrint('[MatchProvider] refresh failed: $e');
    }));
    return repo.getMyMatchesLocal(status: status);
  }

  return repo.getMyMatches(status: status);
});

/// 매칭 상세 프로바이더 (로컬 우선)
final matchDetailProvider =
    FutureProvider.autoDispose.family<Match, String>((ref, matchId) async {
  final repo = ref.read(matchingRepositoryProvider);

  // 로컬에서 먼저 조회
  final local = await repo.getMatchDetailLocal(matchId);
  if (local != null) {
    // 백그라운드로 최신 데이터 갱신
    unawaited(repo.getMatchDetail(matchId).then((_) {}).catchError((e) {
      debugPrint('[MatchProvider] detail refresh failed: $e');
    }));
    return local;
  }

  return repo.getMatchDetail(matchId);
});

/// 매칭 요청 목록 Notifier (AsyncNotifier 기반 — .when() 지원)
class MatchRequestNotifier
    extends AutoDisposeAsyncNotifier<MatchRequestListState> {
  @override
  Future<MatchRequestListState> build() async {
    return _fetchRequests();
  }

  Future<MatchRequestListState> _fetchRequests() async {
    final repo = ref.read(matchingRepositoryProvider);
    final results = await Future.wait([
      repo.getMyMatchRequests(type: 'SENT'),
      repo.getMyMatchRequests(type: 'RECEIVED'),
    ]);
    return MatchRequestListState(
      sent: results[0],
      received: results[1],
    );
  }

  Future<MatchRequest> createRequest(
      Map<String, dynamic> requestData) async {
    final repo = ref.read(matchingRepositoryProvider);
    final request = await repo.createMatchRequest(requestData);
    ref.invalidateSelf();
    return request;
  }

  Future<void> cancelRequest(String requestId) async {
    final repo = ref.read(matchingRepositoryProvider);
    await repo.cancelMatchRequest(requestId);
    ref.invalidateSelf();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final matchRequestProvider =
    AutoDisposeAsyncNotifierProvider<MatchRequestNotifier, MatchRequestListState>(
  MatchRequestNotifier.new,
);

// ─── 매칭 수락/거절 상태 ───
class MatchAcceptState {
  final bool isLoading;
  final String? error;
  final Match? updatedMatch;

  const MatchAcceptState({
    this.isLoading = false,
    this.error,
    this.updatedMatch,
  });

  MatchAcceptState copyWith({
    bool? isLoading,
    String? error,
    Match? updatedMatch,
  }) {
    return MatchAcceptState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      updatedMatch: updatedMatch ?? this.updatedMatch,
    );
  }
}

/// 매칭 수락/거절 Notifier
class MatchAcceptNotifier
    extends AutoDisposeFamilyNotifier<MatchAcceptState, String> {
  Timer? _pollingTimer;

  @override
  MatchAcceptState build(String matchId) {
    ref.onDispose(() {
      _pollingTimer?.cancel();
    });
    return const MatchAcceptState();
  }

  /// 매칭 수락
  Future<Match?> acceptMatch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final match = await repo.acceptMatch(arg);
      state = state.copyWith(isLoading: false, updatedMatch: match);
      return match;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// 매칭 거절
  Future<bool> rejectMatch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.rejectMatch(arg);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// PENDING_ACCEPT 상태일 때 5초마다 상태 폴링 시작
  void startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkMatchStatus();
    });
  }

  /// 폴링 중지
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _checkMatchStatus() async {
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final match = await repo.getMatchStatus(arg);
      state = state.copyWith(updatedMatch: match);
      // CHAT 상태로 전환 시 폴링 중지
      if (match.status != 'PENDING_ACCEPT') {
        stopPolling();
      }
    } catch (_) {
      // 폴링 중 에러는 조용히 무시 (다음 폴링에서 재시도)
    }
  }
}

final matchAcceptProvider = NotifierProvider.autoDispose
    .family<MatchAcceptNotifier, MatchAcceptState, String>(
  MatchAcceptNotifier.new,
);

/// PENDING_ACCEPT 상태 매칭 목록 (홈 화면 배너용)
final pendingAcceptMatchesProvider =
    FutureProvider.autoDispose<List<Match>>((ref) async {
  final repo = ref.read(matchingRepositoryProvider);
  return repo.getMyMatches(status: 'PENDING_ACCEPT');
});
