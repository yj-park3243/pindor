import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match_request.dart';
import '../models/match.dart';
import '../repositories/matching_repository.dart';
import '../core/network/socket_service.dart';
import '../core/storage/secure_storage.dart';

/// 활성 매칭/요청이 있으면 소켓 연결, 없으면 끊기
///
/// invalidateSelf 직후 캐시(loading/null)를 읽지 않도록 fresh fetch 결과를 사용한다.
/// 이미 추적 중인 소켓 룸(`hasActiveRooms`)이 있으면 항상 연결 유지.
///
/// 탭 연타 등으로 짧은 시간에 여러 번 호출되면 fetch 폭주(매칭/요청 목록 API)로
/// rate-limit 에 걸릴 수 있으므로 디바운스로 묶는다.
DateTime? _lastSyncRunAt;
Future<void>? _ongoingSync;
const _syncDebounceMs = 800;

Future<void> syncSocketConnection(dynamic ref) async {
  // 진행 중인 sync 가 있으면 그걸 그대로 반환
  if (_ongoingSync != null) return _ongoingSync;
  // 직전 실행으로부터 디바운스 윈도우 내면 무시
  final last = _lastSyncRunAt;
  if (last != null &&
      DateTime.now().difference(last).inMilliseconds < _syncDebounceMs) {
    return;
  }
  final fut = _runSyncSocketConnection(ref);
  _ongoingSync = fut;
  try {
    await fut;
  } finally {
    _ongoingSync = null;
    _lastSyncRunAt = DateTime.now();
  }
}

Future<void> _runSyncSocketConnection(dynamic ref) async {
  final socket = SocketService.instance;

  // 추적 중인 룸이 있으면 즉시 연결 (가장 강한 신호)
  if (socket.hasActiveRooms && !socket.isConnected) {
    final token = await SecureStorage.instance.getAccessToken();
    if (token != null) {
      debugPrint('[Socket] 활성 룸 있음 — 즉시 연결');
      socket.connect(token);
    }
    return;
  }

  bool hasActiveMatch = false;
  bool hasWaitingRequest = false;

  try {
    final matches = await (ref as dynamic).read(matchListProvider(null).future)
        as List<Match>;
    hasActiveMatch = matches.any((m) =>
        m.isPendingAccept || m.isChat || m.isConfirmed);
  } catch (_) {
    // 매칭 목록 로드 실패 — 이전에 화면에 노출되던 값으로 폴백
    // dynamic.valueOrNull 직접 호출 시 extension getter 가 잡히지 않아
    // NoSuchMethodError 가 발생한다 → 정적 타입으로 캐스팅 후 사용한다.
    final asyncMatches = (ref as dynamic).read(matchListProvider(null))
        as AsyncValue<List<Match>>;
    final cached = asyncMatches.valueOrNull ?? const <Match>[];
    hasActiveMatch = cached.any((m) =>
        m.isPendingAccept || m.isChat || m.isConfirmed);
  }

  try {
    final requests = await (ref as dynamic).read(matchRequestProvider.future)
        as MatchRequestListState;
    hasWaitingRequest = requests.sent.any((r) => r.isWaiting);
  } catch (_) {
    final asyncRequests = (ref as dynamic).read(matchRequestProvider)
        as AsyncValue<MatchRequestListState>;
    final cached = asyncRequests.valueOrNull;
    hasWaitingRequest = cached?.sent.any((r) => r.isWaiting) ?? false;
  }

  if (hasActiveMatch || hasWaitingRequest || socket.hasActiveRooms) {
    if (!socket.isConnected) {
      final token = await SecureStorage.instance.getAccessToken();
      if (token != null) {
        debugPrint('[Socket] 활성 매칭 있음 — 연결');
        socket.connect(token);
      }
    }
  } else {
    if (socket.isConnected) {
      debugPrint('[Socket] 활성 매칭 없음 — 연결 해제');
      socket.disconnect();
    }
  }
}

/// 즉시 소켓 연결 (룸 등록 직후 등 동기적으로 연결을 보장하고 싶을 때)
/// connect() 만 호출하면 비동기로 연결이 진행되어, 직후의 join* emit 이
/// 미연결 상태에서 스킵될 수 있다. 연결 완료(최대 5초)까지 대기한다.
Future<void> ensureSocketConnected() async {
  final socket = SocketService.instance;
  if (socket.isConnected) return;
  final token = await SecureStorage.instance.getAccessToken();
  if (token == null) return;
  socket.connect(token);
  try {
    await socket.onConnectionState
        .firstWhere((connected) => connected)
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // 타임아웃 — onConnect 핸들러가 추적 룸들을 재입장하므로 치명적이지 않다.
  }
}

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

/// 소켓 이벤트 등으로 캐시를 무시하고 서버에서 직접 가져와야 할 때 true로 설정
final matchListForceRefreshProvider = StateProvider<bool>((ref) => false);

/// 매칭 목록 프로바이더 (SWR 패턴)
final matchListProvider = FutureProvider.autoDispose
    .family<List<Match>, String?>((ref, status) async {
  final repo = ref.read(matchingRepositoryProvider);
  final forceRefresh = ref.read(matchListForceRefreshProvider);

  // 소켓 이벤트 등으로 강제 갱신이 필요한 경우 서버에서 직접 가져옴
  if (forceRefresh) {
    // 빌드 중 다른 provider 수정 불가 → microtask로 지연 리셋
    Future.microtask(() => ref.read(matchListForceRefreshProvider.notifier).state = false);
    try {
      return await repo.getMyMatches(status: status);
    } catch (e) {
      // 강제 갱신 실패 시에도 로컬 캐시가 있으면 그걸로 폴백
      debugPrint('[MatchProvider] force refresh failed — fallback to local: $e');
      return repo.getMyMatchesLocal(status: status);
    }
  }

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

  // 첫 fetch — 실패 시 이전 build 의 데이터를 유지하여 화면이 비지 않도록 한다.
  try {
    return await repo.getMyMatches(status: status);
  } catch (e) {
    final previous = ref.state.valueOrNull;
    if (previous != null) {
      debugPrint('[MatchProvider] fetch 실패 — 이전 데이터 유지: $e');
      return previous;
    }
    rethrow;
  }
});

/// 매칭 상세 프로바이더 (로컬 우선, 서버 404 시 캐시 삭제)
final matchDetailProvider =
    FutureProvider.autoDispose.family<Match, String>((ref, matchId) async {
  final repo = ref.read(matchingRepositoryProvider);

  // 로컬에서 먼저 조회 → 서버에서 항상 최신 데이터도 가져옴
  final local = await repo.getMatchDetailLocal(matchId);
  if (local != null) {
    // 서버에서 최신 데이터 가져오기 시도, 실패하면 로컬 반환
    try {
      final fresh = await repo.getMatchDetail(matchId);
      return fresh;
    } catch (e) {
      debugPrint('[MatchProvider] detail refresh failed: $e');
      if (e.toString().contains('MATCH_002') || e.toString().contains('404') || e.toString().contains('찾을 수 없')) {
        repo.clearLocalCache();
        ref.invalidate(matchListProvider(null));
      }
      return local;
    }
  }

  return repo.getMatchDetail(matchId);
});

/// 매칭 요청 목록 Notifier (AsyncNotifier 기반 — .when() 지원)
class MatchRequestNotifier
    extends AutoDisposeAsyncNotifier<MatchRequestListState> {
  @override
  Future<MatchRequestListState> build() async {
    try {
      return await _fetchRequests();
    } catch (e) {
      // 새로고침 실패(네트워크/rate-limit 등) 시, Riverpod 가 invalidate 직전 상태를
      // copyWithPrevious 로 끌고 와줘서 state.valueOrNull 에 직전 데이터가 남아있다.
      // 이 값을 그대로 반환하여 화면에 보이던 매칭 요청 목록이 사라지지 않게 한다.
      final previous = state.valueOrNull;
      if (previous != null) {
        debugPrint('[MatchRequestNotifier] refresh 실패 — 이전 데이터 유지: $e');
        return previous;
      }
      rethrow;
    }
  }

  Future<MatchRequestListState> _fetchRequests() async {
    final repo = ref.read(matchingRepositoryProvider);
    final results = await Future.wait([
      repo.getMyMatchRequests(type: 'SENT', status: 'WAITING'),
      repo.getMyMatchRequests(type: 'RECEIVED', status: 'WAITING'),
    ]);
    // desiredDate 오름차순 정렬 (오늘 → 내일)
    final sent = results[0]..sort((a, b) {
      final da = a.desiredDate ?? '';
      final db = b.desiredDate ?? '';
      return da.compareTo(db);
    });

    // 앱 재시작 등으로 진행 중인 WAITING 매칭 요청의 socket 룸을 복구한다.
    // 이 복구가 없으면 부팅 후 매칭이 성사돼도 MATCH_FOUND 이벤트를 못 받는다.
    for (final r in sent) {
      if (r.isWaiting) {
        SocketService.instance.joinMatchRequest(r.id);
      }
    }

    return MatchRequestListState(
      sent: sent,
      received: results[1],
    );
  }

  Future<MatchRequest> createRequest(
      Map<String, dynamic> requestData) async {
    final repo = ref.read(matchingRepositoryProvider);
    final request = await repo.createMatchRequest(requestData);
    debugPrint('[Match] createRequest 완료 — id=${request.id} status=${request.status}');
    ref.invalidateSelf();

    // WAITING 상태인 경우 소켓 룸에 입장하여 실시간 매칭 성사 알림 수신
    if (request.status == 'WAITING') {
      // 먼저 연결을 완료(대기)한 뒤 룸에 입장해야 emit 이 실제로 전송된다.
      debugPrint('[Match] joinMatchRequest 룸 입장 — requestId=${request.id}');
      await ensureSocketConnected();
      SocketService.instance.joinMatchRequest(request.id);
    }

    return request;
  }

  Future<void> cancelRequest(String requestId) async {
    debugPrint('[Match] cancelRequest 시작 — requestId=$requestId');
    // 매칭 요청 취소 전 소켓 룸에서 퇴장
    SocketService.instance.leaveMatchRequest(requestId);

    final repo = ref.read(matchingRepositoryProvider);
    await repo.cancelMatchRequest(requestId);
    debugPrint('[Match] cancelRequest 완료 — requestId=$requestId');
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
  StreamSubscription<Map<String, dynamic>>? _matchStatusSub;
  StreamSubscription<bool>? _connectionSub;
  int _failureCount = 0;
  int _pollIntervalSeconds = 10; // exponential backoff 시작 인터벌

  static const _maxPollIntervalSeconds = 60;
  static const _maxFailureCount = 5;

  @override
  MatchAcceptState build(String matchId) {
    ref.onDispose(() {
      _pollingTimer?.cancel();
      _socketSub?.cancel();
      _matchStatusSub?.cancel();
      _connectionSub?.cancel();
    });
    return const MatchAcceptState();
  }

  /// 매칭 수락 — 서버 응답: { status: 'WAITING_OPPONENT' | 'MATCHED', chatRoomId? }
  Future<bool> acceptMatch() async {
    debugPrint('[Match] acceptMatch 호출 — matchId=$arg');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final data = await repo.acceptMatch(arg);
      final status = data['status'] as String?;
      final chatRoomId = data['chatRoomId'] as String?;
      debugPrint('[Match] acceptMatch 응답 — matchId=$arg status=$status chatRoomId=$chatRoomId');
      state = state.copyWith(
        isLoading: false,
        acceptStatus: status,
        chatRoomId: chatRoomId,
      );
      return true;
    } catch (e) {
      debugPrint('[Match] acceptMatch 실패 — matchId=$arg error=$e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// 매칭 거절 — 서버 응답: { status: 'CANCELLED' }
  Future<bool> rejectMatch() async {
    debugPrint('[Match] rejectMatch 호출 — matchId=$arg');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.rejectMatch(arg);
      debugPrint('[Match] rejectMatch 완료 — matchId=$arg');
      state = state.copyWith(isLoading: false, acceptStatus: 'CANCELLED');
      return true;
    } catch (e) {
      debugPrint('[Match] rejectMatch 실패 — matchId=$arg error=$e');
      String errorMsg = e.toString();
      if (e is DioException && e.response?.data is Map) {
        final serverError = e.response!.data['error'];
        if (serverError is Map && serverError['message'] != null) {
          errorMsg = serverError['message'] as String;
        }
      }
      state = state.copyWith(isLoading: false, error: errorMsg);
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

      if (type == 'MATCH_BOTH_ACCEPTED' || type == 'MATCH_ACCEPTED') {
        _socketSub?.cancel();
        _pollingTimer?.cancel();
        debugPrint('[Match] 상대 수락 수신 (Notifier) — matchId=$arg type=$type');
        _fetchMatchDetailAndUpdate();
      } else if (type == 'MATCH_CANCELLED' || type == 'MATCH_REJECTED' || type == 'MATCH_ACCEPT_TIMEOUT') {
        _socketSub?.cancel();
        _pollingTimer?.cancel();
        debugPrint('[Match] 매칭 종료 수신 (Notifier) — matchId=$arg type=$type');
        state = state.copyWith(acceptStatus: 'CANCELLED');
      }
    });

    // MATCH_STATUS_CHANGED 소켓 이벤트도 감지 (match:{matchId} 룸 기반)
    _matchStatusSub?.cancel();
    _matchStatusSub = SocketService.instance.onMatchStatusChanged.listen((data) {
      final matchId = data['matchId'] as String?;
      final status = data['status'] as String?;
      if (matchId != arg) return;

      if (status == 'CANCELLED') {
        _socketSub?.cancel();
        _matchStatusSub?.cancel();
        _pollingTimer?.cancel();
        debugPrint('[Match] MATCH_STATUS_CHANGED CANCELLED — matchId=$arg');
        state = state.copyWith(acceptStatus: 'CANCELLED');
      } else if (status == 'CHAT') {
        _socketSub?.cancel();
        _matchStatusSub?.cancel();
        _pollingTimer?.cancel();
        debugPrint('[Match] MATCH_STATUS_CHANGED CHAT — matchId=$arg');
        _fetchMatchDetailAndUpdate();
      }
    });

    // 소켓 연결이 끊기면 폴링으로 전환
    _connectionSub?.cancel();
    _connectionSub = SocketService.instance.onConnectionState.listen((connected) {
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
    _connectionSub?.cancel();
    _connectionSub = null;
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
