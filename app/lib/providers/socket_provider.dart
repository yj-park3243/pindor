import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';

/// 소켓 연결 상태 프로바이더
final socketConnectionProvider = StreamProvider<bool>((ref) {
  return SocketService.instance.onConnectionState;
});

/// 실시간 알림 스트림 프로바이더
final socketNotificationProvider =
    StreamProvider<Map<String, dynamic>>((ref) {
  return SocketService.instance.onNotification;
});

/// 실시간 메시지 스트림 프로바이더 (채팅방에서 사용)
final socketMessageProvider =
    StreamProvider<Map<String, dynamic>>((ref) {
  return SocketService.instance.onNewMessage;
});

/// 타이핑 상태 스트림 프로바이더
final socketTypingProvider =
    StreamProvider<Map<String, dynamic>>((ref) {
  return SocketService.instance.onTyping;
});

/// 특정 채팅방의 메시지 스트림
final roomMessageProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, roomId) {
  return SocketService.instance.onNewMessage
      .where((data) => data['roomId'] == roomId);
});

/// 매칭 성사 이벤트 스트림 프로바이더 (matchrequest:{requestId} 룸 기반)
/// MATCH_FOUND 이벤트 수신 시 { matchId, status } 데이터 전달
final socketMatchFoundProvider =
    StreamProvider<Map<String, dynamic>>((ref) {
  return SocketService.instance.onMatchFound;
});

/// 매칭 상태 변경 이벤트 스트림 프로바이더 (match:{matchId} 룸 기반)
/// MATCH_STATUS_CHANGED 이벤트 수신 시 { matchId, status, ... } 데이터 전달
final socketMatchStatusChangedProvider =
    StreamProvider<Map<String, dynamic>>((ref) {
  return SocketService.instance.onMatchStatusChanged;
});

/// 소켓 서비스 접근 프로바이더
final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService.instance;
});
