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

/// 소켓 서비스 접근 프로바이더
final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService.instance;
});
