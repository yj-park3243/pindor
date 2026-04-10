import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match_request.dart';
import '../models/match.dart';
import '../repositories/matching_repository.dart';
import '../core/network/socket_service.dart';

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
    // 항상 백그라운드 갱신 — 서버 응답으로 로컬 캐시 교체
    unawaited(repo.getMyMatches().then((serverMatches) {
      // 서버 결과가 비어있으면 로컬 캐시도 정리
      if (serverMatches.isEmpty) {
        repo.clearLocalCache();
      }
    }).catchError((e) {
      debugPrint('[MatchProvider] refresh failed: $e');
    }));
    return repo.getMyMatchesLocal(status: status);
  }

  return repo.getMyMatches(status: status);
});

/// 매칭 상세 프로바이더 (로컬 우선, 서버 404 시 캐시 삭제)
final matchDetailProvider =
    FutureProvider.autoDispose.family<Match, String>((ref, matchId) async {
  final repo = ref.read(matchingRepositoryProvider);

  // 로컬에서 먼저 조회
  final local = await repo.getMatchDetailLocal(matchId);
  if (local != null) {
    // 백그라운드로 최신 데이터 갱신 — 404 시 로컬 캐시 삭제
    unawaited(repo.getMatchDetail(matchId).then((_) {}).catchError((e) {
      debugPrint('[MatchProvider] detail refresh failed: $e');
      // 서버에서 매칭을 찾을 수 없으면 로컬 캐시 정리
      if (e.toString().contains('MATCH_002') || e.toString().contains('404') || e.toString().contains('찾을 수 없')) {
        repo.clearLocalCache();
        ref.invalidate(matchListProvider(null));
      }
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
    // desiredDate 오름차순 정렬 (오늘 → 내일)
    final sent = results[0]..sort((a, b) {
      final da = a.desiredDate ?? '';
      final db = b.desiredDate ?? '';
      return da.compareTo(db);
    });
    return MatchRequestListState(
      sent: sent,
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
  final String? acceptStatus; // WAITING_OPPONENT | MATCHED | CANCELLED
  final String? chatRoomId; // MATCHED 시 서버에서 반환되는 채팅방 ID

  const MatchAcceptState({
    this.isLoading = false,
    this.error,
    this.updatedMatch,
    this.acceptStatus,
    this.chatRoomId,
  });

  MatchAcceptState copyWith({
    bool? isLoading,
    String? error,
    Match? updatedMatch,
    String? acceptStatus,
    String? chatRoomId,
  }) {
    return MatchAcceptState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      updatedMatch: updatedMatch ?? this.updatedMatch,
      acceptStatus: acceptStatus ?? this.acceptStatus,
      chatRoomId: chatRoomId ?? this.chatRoomId,
    );
  }
}

/// 매칭 수락/거절 Notifier
///
/// 상태 변경 감지 전략 (우선순위):
/// 1. 소켓 notification 이벤트에서 MATCH_ACCEPTED / MATCH_CANCELLED 수신 시 즉시 처리
/// 2. 소켓이 연결되지 않은 경우 폴링 fallback (10초 기본, 연속 실패 시 exponential backoff)
class MatchAcceptNotifier
    extends AutoDisposeFamilyNotifier<MatchAcceptState, String> {
  Timer? _pollingTimer;
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  int _failureCount = 0;
  int _pollIntervalSeconds = 10; // exponential backoff 시작 인터벌

  static const _maxPollIntervalSeconds = 60;
  static const _maxFailureCount = 5;

  @override
  MatchAcceptState build(String matchId) {
    ref.onDispose(() {
      _pollingTimer?.cancel();
      _socketSub?.cancel();
    });
    return const MatchAcceptState();
  }

  /// 매칭 수락 — 서버 응답: { status: 'WAITING_OPPONENT' | 'MATCHED', chatRoomId? }
  Future<bool> acceptMatch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final data = await repo.acceptMatch(arg);
      final status = data['status'] as String?;
      final chatRoomId = data['chatRoomId'] as String?;
      state = state.copyWith(
        isLoading: false,
        acceptStatus: status,
        chatRoomId: chatRoomId,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// 매칭 거절 — 서버 응답: { status: 'CANCELLED' }
  Future<bool> rejectMatch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.rejectMatch(arg);
      state = state.copyWith(isLoading: false, acceptStatus: 'CANCELLED');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// PENDING_ACCEPT 상태 대기 시작
  ///
  /// 소켓이 연결되어 있으면 소켓 이벤트를 우선 구독하고,
  /// 연결되지 않은 경우 폴링 fallback을 사용한다.
  void startPolling() {
    _socketSub?.cancel();
    _pollingTimer?.cancel();
    _failureCount = 0;
    _pollIntervalSeconds = 10;

    final socket = SocketService.instance;
    if (socket.isConnected) {
      _listenSocket();
    } else {
      // 소켓 미연결: 폴링 fallback
      _scheduleNextPoll();
    }
  }

  /// 소켓 notification 스트림 구독
  /// MATCH_ACCEPTED / MATCH_CANCELLED 이벤트로 이 매칭의 상태 변경을 감지한다.
  void _listenSocket() {
    _socketSub = SocketService.instance.onNotification.listen((data) {
      final type = data['type'] as String? ?? '';
      final matchId = data['data']?['matchId'] as String?;

      // 이 Notifier가 담당하는 matchId와 무관한 이벤트는 무시
      if (matchId != null && matchId != arg) return;

      if (type == 'MATCH_ACCEPTED') {
        _socketSub?.cancel();
        _pollingTimer?.cancel();
        debugPrint('[MatchAccept] 소켓으로 MATCH_ACCEPTED 수신 — 상세 조회');
        _fetchMatchDetailAndUpdate();
      } else if (type == 'MATCH_CANCELLED') {
        _socketSub?.cancel();
        _pollingTimer?.cancel();
        state = state.copyWith(acceptStatus: 'CANCELLED');
      }
    });

    // 소켓 연결이 끊기면 폴링으로 전환
    SocketService.instance.onConnectionState.listen((connected) {
      if (!connected && _socketSub != null) {
        debugPrint('[MatchAccept] 소켓 연결 끊김 — 폴링으로 전환');
        _socketSub?.cancel();
        _socketSub = null;
        _scheduleNextPoll();
      }
    });
  }

  /// 다음 폴링을 스케줄 (exponential backoff)
  void _scheduleNextPoll() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer(Duration(seconds: _pollIntervalSeconds), () async {
      await _checkMatchStatus();
    });
  }

  /// 폴링 중지
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _socketSub?.cancel();
    _socketSub = null;
  }

  Future<void> _checkMatchStatus() async {
    try {
      final repo = ref.read(matchingRepositoryProvider);
      // 서버 /matches/:id/status는 수락 상태 요약만 반환 (Match 전체 아님)
      final statusResponse = await repo.getMatchStatus(arg);
      _failureCount = 0;
      _pollIntervalSeconds = 10; // 성공 시 인터벌 초기화

      // PENDING_ACCEPT에서 벗어나면 폴링 중지 후 상세 조회로 updatedMatch 채우기
      if (statusResponse.status != 'PENDING_ACCEPT') {
        stopPolling();
        await _fetchMatchDetailAndUpdate(fallbackStatus: statusResponse.status);
      } else {
        // 아직 PENDING_ACCEPT — 다음 폴링 예약
        _scheduleNextPoll();
      }
    } catch (_) {
      _failureCount++;
      if (_failureCount >= _maxFailureCount) {
        debugPrint('[Polling] 연속 $_failureCount회 실패로 폴링 중지');
        stopPolling();
        return;
      }
      // Exponential backoff: 10 → 20 → 40 → ... → 60초 상한
      _pollIntervalSeconds = (_pollIntervalSeconds * 2)
          .clamp(10, _maxPollIntervalSeconds);
      debugPrint('[Polling] 실패 $_failureCount회 — ${_pollIntervalSeconds}초 후 재시도');
      _scheduleNextPoll();
    }
  }

  Future<void> _fetchMatchDetailAndUpdate({String? fallbackStatus}) async {
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final match = await repo.getMatchDetail(arg);
      state = state.copyWith(updatedMatch: match);
    } catch (_) {
      // 상세 조회 실패 시 acceptStatus만 갱신하여 UI 이동이 가능하도록 처리
      if (fallbackStatus != null) {
        state = state.copyWith(acceptStatus: fallbackStatus);
      }
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
