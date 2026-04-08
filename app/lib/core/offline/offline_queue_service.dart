import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database.dart';
import '../../data/local/database_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/socket_service.dart';

/// 오프라인 쓰기 큐 서비스
///
/// 네트워크 없을 때 쓰기 작업을 로컬 DB에 저장하고,
/// 네트워크 복귀 시 순서대로 서버에 전송합니다.
class OfflineQueueService {
  final AppDatabase _db;
  final ApiClient _api;

  StreamSubscription<dynamic>? _connectivitySub;
  bool _isProcessing = false;

  static const int _maxRetries = 5;

  OfflineQueueService(this._db, this._api);

  /// 네트워크 상태 감시 시작
  void startListening() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      // connectivity_plus v5: ConnectivityResult (단일 값)
      final hasConnection = result != ConnectivityResult.none;
      if (hasConnection) {
        processQueue();
      }
    });
  }

  /// 감시 중지
  void stopListening() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// 큐에 작업 추가
  Future<void> enqueue({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final now = DateTime.now();
    await _db.into(_db.offlineQueue).insert(
      OfflineQueueCompanion(
        action: Value(action),
        payloadJson: Value(jsonEncode(payload)),
        status: const Value('PENDING'),
        retryCount: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    debugPrint('[OfflineQueue] 작업 추가: $action');
  }

  /// 큐 처리 (PENDING 작업을 순서대로 실행)
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final pending = await (_db.select(_db.offlineQueue)
              ..where((t) => t.status.equals('PENDING'))
              ..orderBy([(t) => OrderingTerm.asc(t.id)])
              ..limit(1))
            .getSingleOrNull();

        if (pending == null) break;

        // PROCESSING 상태로 변경
        await (_db.update(_db.offlineQueue)
              ..where((t) => t.id.equals(pending.id)))
            .write(OfflineQueueCompanion(
          status: const Value('PROCESSING'),
          updatedAt: Value(DateTime.now()),
        ));

        try {
          await _executeAction(pending.action, pending.payloadJson);

          // 성공 → 삭제
          await (_db.delete(_db.offlineQueue)
                ..where((t) => t.id.equals(pending.id)))
              .go();
          debugPrint('[OfflineQueue] 성공: ${pending.action} #${pending.id}');
        } catch (e) {
          final newRetry = pending.retryCount + 1;
          if (newRetry >= _maxRetries) {
            // 최대 재시도 초과 → FAILED
            await (_db.update(_db.offlineQueue)
                  ..where((t) => t.id.equals(pending.id)))
                .write(OfflineQueueCompanion(
              status: const Value('FAILED'),
              retryCount: Value(newRetry),
              lastError: Value(e.toString()),
              updatedAt: Value(DateTime.now()),
            ));
            debugPrint('[OfflineQueue] 최대 재시도 초과: ${pending.action} #${pending.id}');
          } else {
            // 재시도 대기 → PENDING으로 복원
            await (_db.update(_db.offlineQueue)
                  ..where((t) => t.id.equals(pending.id)))
                .write(OfflineQueueCompanion(
              status: const Value('PENDING'),
              retryCount: Value(newRetry),
              lastError: Value(e.toString()),
              updatedAt: Value(DateTime.now()),
            ));
            debugPrint('[OfflineQueue] 재시도 ${newRetry}/$_maxRetries: ${pending.action}');
            // exponential backoff
            await Future.delayed(Duration(seconds: 1 << newRetry));
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// 실패한 작업 재시도 (FAILED → PENDING)
  Future<int> retryFailed() async {
    final count = await (_db.update(_db.offlineQueue)
          ..where((t) => t.status.equals('FAILED')))
        .write(OfflineQueueCompanion(
      status: const Value('PENDING'),
      retryCount: const Value(0),
      updatedAt: Value(DateTime.now()),
    ));
    if (count > 0) unawaited(processQueue());
    return count;
  }

  /// 대기 중인 작업 수
  Future<int> getPendingCount() async {
    final count = countAll();
    final query = _db.selectOnly(_db.offlineQueue)
      ..addColumns([count])
      ..where(_db.offlineQueue.status.equals('PENDING'));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 작업 실행
  Future<void> _executeAction(String action, String payloadJson) async {
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

    switch (action) {
      case 'SEND_MESSAGE':
        final roomId = payload['roomId'] as String;
        final content = payload['content'] as String;
        final messageType = payload['messageType'] as String? ?? 'TEXT';

        if (SocketService.instance.isConnected) {
          SocketService.instance.sendMessage(roomId, content, type: messageType);
        } else {
          await _api.post(
            '/chat-rooms/$roomId/messages',
            body: {'messageType': messageType, 'content': content},
          );
        }

      case 'CREATE_POST':
        final pinId = payload['pinId'] as String;
        await _api.post('/pins/$pinId/posts', body: {
          'title': payload['title'],
          'content': payload['content'],
          'category': payload['category'],
          'imageUrls': payload['imageUrls'] ?? [],
        });

      case 'CREATE_COMMENT':
        final pinId = payload['pinId'] as String;
        final postId = payload['postId'] as String;
        await _api.post('/pins/$pinId/posts/$postId/comments', body: {
          'content': payload['content'],
          if (payload['parentId'] != null) 'parentId': payload['parentId'],
        });

      default:
        debugPrint('[OfflineQueue] 알 수 없는 action: $action');
    }
  }
}

/// OfflineQueueService Provider
final offlineQueueServiceProvider = Provider<OfflineQueueService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final service = OfflineQueueService(db, ApiClient.instance);
  service.startListening();
  ref.onDispose(() => service.stopListening());
  return service;
});

/// 네트워크 연결 상태 Provider
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (result) => result != ConnectivityResult.none,
  );
});
