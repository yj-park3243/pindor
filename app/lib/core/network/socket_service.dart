import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/app_config.dart';

/// Socket.io 연결 관리 서비스 (PRD 4.10.9 기반)
/// - 앱 전역 싱글톤으로 관리
/// - 자동 재연결 (최대 10회, 1초 간격)
/// - 채팅 메시지 / 알림 / 매칭 라이프사이클 스트림 제공
class SocketService {
  SocketService._();

  static final SocketService _instance = SocketService._();
  static SocketService get instance => _instance;

  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentAccessToken;
  String? _activeRoomId;

  // 매칭 요청 룸 추적 (재연결 시 자동 재입장용)
  final Set<String> _activeMatchRequestRooms = {};
  // 매칭 룸 추적 (재연결 시 자동 재입장용)
  final Set<String> _activeMatchRooms = {};

  // ─── 스트림 컨트롤러 ───
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messagesReadController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 매칭 라이프사이클 스트림 컨트롤러
  final _matchFoundController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _matchStatusChangedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─── 스트림 공개 인터페이스 ───
  Stream<Map<String, dynamic>> get onNotification =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get onNewMessage => _messageController.stream;
  Stream<bool> get onConnectionState => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onMessagesRead =>
      _messagesReadController.stream;

  /// 매칭 성사 이벤트 스트림 (matchrequest:{requestId} 룸 기반)
  Stream<Map<String, dynamic>> get onMatchFound => _matchFoundController.stream;

  /// 매칭 상태 변경 이벤트 스트림 (match:{matchId} 룸 기반)
  Stream<Map<String, dynamic>> get onMatchStatusChanged =>
      _matchStatusChangedController.stream;

  bool get isConnected => _isConnected;
  String? get activeRoomId => _activeRoomId;

  /// 소켓 연결 (로그인 후 호출)
  void connect(String accessToken) {
    if (_isConnected && _currentAccessToken == accessToken) {
      debugPrint('[Socket] 이미 연결됨');
      return;
    }

    _currentAccessToken = accessToken;
    _disconnect();

    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/ws')
          .setAuth({'token': accessToken})
          .enableReconnection()
          .setReconnectionDelay(AppConfig.socketReconnectDelay)
          .setReconnectionAttempts(AppConfig.socketMaxReconnectAttempts)
          .disableAutoConnect()
          .build(),
    );

    _registerHandlers();
    _socket!.connect();
  }

  void _registerHandlers() {
    // 재연결 등으로 인한 중복 리스너 방지: 등록 전 이전 핸들러 제거
    _socket!
      ..off('notification')
      ..off('NEW_MESSAGE')
      ..off('USER_TYPING')
      ..off('MESSAGES_READ')
      ..off('MATCH_FOUND')
      ..off('MATCH_STATUS_CHANGED')
      ..off('ERROR');

    _socket!
      ..onConnect((_) {
        _isConnected = true;
        _connectionStateController.add(true);
        debugPrint('[Socket] 연결됨');
      })
      ..onDisconnect((_) {
        _isConnected = false;
        _connectionStateController.add(false);
        debugPrint('[Socket] 연결 끊김');
      })
      ..onConnectError((error) {
        debugPrint('[Socket] 연결 오류: $error');
      })
      ..onReconnect((_) {
        debugPrint('[Socket] 재연결됨');
        // 재연결 시 현재 채팅방 자동 재입장
        if (_activeRoomId != null) {
          joinRoom(_activeRoomId!);
        }
        // 재연결 시 매칭 요청 룸 자동 재입장
        for (final requestId in _activeMatchRequestRooms) {
          _socket?.emit('JOIN_MATCH_REQUEST', {'requestId': requestId});
          debugPrint('[Socket] 재연결 후 매칭 요청 룸 재입장: $requestId');
        }
        // 재연결 시 매칭 룸 자동 재입장
        for (final matchId in _activeMatchRooms) {
          _socket?.emit('JOIN_MATCH', {'matchId': matchId});
          debugPrint('[Socket] 재연결 후 매칭 룸 재입장: $matchId');
        }
      })

      // 실시간 알림 수신 (매칭, 점수 변동 등)
      ..on('notification', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _notificationController.add(parsed);
        debugPrint('[Socket] 알림 수신: ${parsed['type']}');
      })

      // 채팅 메시지 수신
      ..on('NEW_MESSAGE', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _messageController.add(parsed);
      })

      // 타이핑 상태 수신
      ..on('USER_TYPING', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _typingController.add(parsed);
      })

      // 읽음 처리 수신
      ..on('MESSAGES_READ', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _messagesReadController.add(parsed);
      })

      // 매칭 성사 이벤트 수신 (matchrequest:{requestId} 룸)
      ..on('MATCH_FOUND', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _matchFoundController.add(parsed);
        debugPrint('[Socket] 매칭 성사: ${parsed['matchId']}');
      })

      // 매칭 상태 변경 이벤트 수신 (match:{matchId} 룸)
      ..on('MATCH_STATUS_CHANGED', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _matchStatusChangedController.add(parsed);
        debugPrint('[Socket] 매칭 상태 변경: ${parsed['matchId']} → ${parsed['status']}');
      })

      // 소켓 에러
      ..on('ERROR', (data) {
        debugPrint('[Socket] 서버 에러: $data');
      });
  }

  /// 채팅방 입장
  void joinRoom(String roomId) {
    if (!_isConnected) return;
    _activeRoomId = roomId;
    _socket!.emit('JOIN_ROOM', {'roomId': roomId});
    debugPrint('[Socket] 채팅방 입장: $roomId');
  }

  /// 채팅방 퇴장
  void leaveRoom(String roomId) {
    if (!_isConnected) return;
    if (_activeRoomId == roomId) {
      _activeRoomId = null;
    }
    _socket!.emit('LEAVE_ROOM', {'roomId': roomId});
    debugPrint('[Socket] 채팅방 퇴장: $roomId');
  }

  /// 메시지 전송
  /// 연결되지 않은 상태에서 호출 시 [SocketNotConnectedException]을 throw합니다.
  void sendMessage(
    String roomId,
    String content, {
    String type = 'TEXT',
    Map<String, dynamic>? extraData,
  }) {
    if (!_isConnected || _socket == null) {
      debugPrint('[Socket] 연결 안됨 - 메시지 전송 실패');
      throw SocketNotConnectedException();
    }
    final payload = <String, dynamic>{
      'roomId': roomId,
      'content': content,
      'messageType': type,
    };
    if (extraData != null) {
      payload['extraData'] = extraData;
    }
    _socket!.emit('SEND_MESSAGE', payload);
  }

  /// 타이핑 상태 전송
  void sendTyping(String roomId) {
    if (!_isConnected) return;
    _socket!.emit('TYPING', {'roomId': roomId});
  }

  /// 매칭 요청 룸 입장 (매칭 성사 알림 수신용)
  void joinMatchRequest(String requestId) {
    if (!_isConnected) return;
    _activeMatchRequestRooms.add(requestId);
    _socket!.emit('JOIN_MATCH_REQUEST', {'requestId': requestId});
    debugPrint('[Socket] 매칭 요청 룸 입장: $requestId');
  }

  /// 매칭 요청 룸 퇴장
  void leaveMatchRequest(String requestId) {
    if (!_isConnected) return;
    _activeMatchRequestRooms.remove(requestId);
    _socket!.emit('LEAVE_MATCH_REQUEST', {'requestId': requestId});
    debugPrint('[Socket] 매칭 요청 룸 퇴장: $requestId');
  }

  /// 매칭 룸 입장 (매칭 상태 변경 알림 수신용)
  void joinMatch(String matchId) {
    if (!_isConnected) return;
    _activeMatchRooms.add(matchId);
    _socket!.emit('JOIN_MATCH', {'matchId': matchId});
    debugPrint('[Socket] 매칭 룸 입장: $matchId');
  }

  /// 매칭 룸 퇴장
  void leaveMatch(String matchId) {
    if (!_isConnected) return;
    _activeMatchRooms.remove(matchId);
    _socket!.emit('LEAVE_MATCH', {'matchId': matchId});
    debugPrint('[Socket] 매칭 룸 퇴장: $matchId');
  }

  /// 연결 해제 (로그아웃 시 호출)
  void disconnect() {
    _activeMatchRequestRooms.clear();
    _activeMatchRooms.clear();
    _disconnect();
    _currentAccessToken = null;
    _activeRoomId = null;
    _isConnected = false; // _socket이 이미 null이었던 경우에도 확실히 초기화
  }

  void _disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
    }
  }

  /// 읽음 처리 전송
  void sendMarkRead(String roomId) {
    if (!_isConnected) return;
    _socket!.emit('MARK_READ', {'roomId': roomId});
  }

  /// 리소스 정리
  void dispose() {
    _activeMatchRequestRooms.clear();
    _activeMatchRooms.clear();
    _disconnect();
    _notificationController.close();
    _messageController.close();
    _connectionStateController.close();
    _typingController.close();
    _messagesReadController.close();
    _matchFoundController.close();
    _matchStatusChangedController.close();
  }
}

/// 소켓 연결 상태 enum
enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 소켓 미연결 상태에서 메시지 전송 시도 시 발생하는 예외
class SocketNotConnectedException implements Exception {
  @override
  String toString() => '소켓이 연결되지 않았습니다. 메시지를 전송할 수 없습니다.';
}
