import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/app_config.dart';
import '../storage/secure_storage.dart';

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
  // 연결 핸드셰이크 진행 중 플래그. 여러 provider 가 동시에 connect() 를 호출하면
  // 소켓이 생성/dispose 되며 경쟁하여 onConnect 의 JOIN_ROOM emit 이 유실된다.
  bool _connecting = false;
  String? _currentAccessToken;
  String? _activeRoomId;

  // 매칭 요청 룸 추적 (재연결 시 자동 재입장용)
  final Set<String> _activeMatchRequestRooms = {};
  // 매칭 룸 추적 (재연결 시 자동 재입장용)
  final Set<String> _activeMatchRooms = {};
  // 서버로부터 ROOM_JOINED ack 를 받은 채팅방 — 재연결 직후 즉시 emit 한
  // JOIN_ROOM 은 transport 가 ready 되기 전이라 유실될 수 있어 ack 로 확인한다.
  final Set<String> _joinedRooms = {};

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
  final _matchMetUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─── 스트림 공개 인터페이스 ───
  Stream<Map<String, dynamic>> get onNotification =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get onNewMessage => _messageController.stream;
  Stream<bool> get onConnectionState => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onMessagesRead =>
      _messagesReadController.stream;

  // 구독자가 아직 없을 때 도착한 MATCH_FOUND 를 잠시 보관한다.
  // 리스너 등록이 이벤트보다 늦어도(앱 부팅 직후 등) 30초 내면 replay 된다.
  Map<String, dynamic>? _bufferedMatchFound;
  DateTime? _bufferedMatchFoundAt;

  /// 매칭 성사 이벤트 스트림 (matchrequest:{requestId} 룸 기반)
  /// 최근 30초 내 도착한 MATCH_FOUND 가 있으면 구독 즉시 replay 한다.
  Stream<Map<String, dynamic>> get onMatchFound async* {
    final buffered = _bufferedMatchFound;
    final at = _bufferedMatchFoundAt;
    if (buffered != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 30)) {
      yield buffered;
    }
    yield* _matchFoundController.stream;
  }

  /// 매칭 상태 변경 이벤트 스트림 (match:{matchId} 룸 기반)
  Stream<Map<String, dynamic>> get onMatchStatusChanged =>
      _matchStatusChangedController.stream;

  /// 우리 만났어요 confirm 변경 이벤트 스트림 (match:{matchId} 룸 기반)
  Stream<Map<String, dynamic>> get onMatchMetUpdated =>
      _matchMetUpdatedController.stream;

  bool get isConnected => _isConnected;
  String? get activeRoomId => _activeRoomId;

  /// 소켓 연결 (로그인 후 호출)
  void connect(String accessToken) {
    if (_isConnected && _currentAccessToken == accessToken) {
      debugPrint('[Socket] 이미 연결됨');
      return;
    }
    if (_connecting) {
      // 핸드셰이크 진행 중 — 중복 connect() 는 소켓 경쟁을 유발하므로 무시.
      debugPrint('[Socket] 연결 시도 중 — 중복 connect 무시');
      return;
    }

    _connecting = true;
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

  /// 룸 입장 직전 호출 — 미연결 상태면 재연결을 촉진한다.
  /// 미연결이면 항상 connect() 로 깨끗하게 새 소켓을 만든다.
  /// (_socket!.connect() 로 어중간하게 재연결하면 onConnect/onReconnect 타이밍이
  /// 어긋나 _activeRoomId 룸 재입장이 누락된다 — 새 소켓이면 onConnect 가 확실히
  /// 호출되어 추적 중인 모든 룸을 재입장한다.)
  /// 토큰은 캐시 → SecureStorage 순으로 확보한다 (앱 부팅 직후엔 둘 다 없을 수 있음).
  Future<void> _ensureConnected() async {
    if (_isConnected) return;
    final token =
        _currentAccessToken ?? await SecureStorage.instance.getAccessToken();
    if (token != null) {
      connect(token);
    }
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
      ..off('MATCH_MET_UPDATED')
      ..off('ROOM_JOINED')
      ..off('ERROR');

    _socket!
      ..onConnect((_) {
        _isConnected = true;
        _connecting = false;
        _connectionStateController.add(true);
        debugPrint('[Socket] 연결됨');
        // 연결 직후 추적 중인 룸들 자동 입장 (createRequest 등에서 미리 등록한 룸 포함)
        if (_activeRoomId != null) {
          // 재연결 직후 즉시 emit 은 유실될 수 있어 ack 기반 재시도로 입장.
          _emitJoinRoomWithRetry(_activeRoomId!, 0);
        }
        for (final requestId in _activeMatchRequestRooms) {
          _socket?.emit('JOIN_MATCH_REQUEST', {'requestId': requestId});
          debugPrint('[Socket] 연결 후 매칭 요청 룸 자동 입장: $requestId');
        }
        for (final matchId in _activeMatchRooms) {
          _socket?.emit('JOIN_MATCH', {'matchId': matchId});
          debugPrint('[Socket] 연결 후 매칭 룸 자동 입장: $matchId');
        }
      })
      ..onDisconnect((_) {
        _isConnected = false;
        _connecting = false;
        // 끊기면 룸 ack 무효 — 재연결 시 다시 JOIN_ROOM ack 를 받아야 한다.
        _joinedRooms.clear();
        _connectionStateController.add(false);
        debugPrint('[Socket] 연결 끊김');
      })
      ..onConnectError((error) {
        _connecting = false;
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
        debugPrint('[Socket] NEW_MESSAGE 수신: room=${parsed['roomId']} content=${parsed['content']}');
      })

      // 채팅방 입장 ack — JOIN_ROOM emit 이 서버에 도달했음을 확인
      ..on('ROOM_JOINED', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        final rid = parsed['roomId'] as String?;
        if (rid != null) {
          _joinedRooms.add(rid);
          debugPrint('[Socket] ROOM_JOINED ack: $rid');
        }
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
        _bufferedMatchFound = parsed;
        _bufferedMatchFoundAt = DateTime.now();
        _matchFoundController.add(parsed);
        debugPrint('[Socket] 매칭 성사: ${parsed['matchId']}');
      })

      // 매칭 상태 변경 이벤트 수신 (match:{matchId} 룸)
      ..on('MATCH_STATUS_CHANGED', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _matchStatusChangedController.add(parsed);
        debugPrint('[Socket] 매칭 상태 변경: ${parsed['matchId']} → ${parsed['status']}');
      })

      // 우리 만났어요 confirm 변경 이벤트 수신 (match:{matchId} 룸)
      ..on('MATCH_MET_UPDATED', (data) {
        final parsed = Map<String, dynamic>.from(data as Map);
        _matchMetUpdatedController.add(parsed);
        debugPrint('[Socket] 만남 확인 업데이트: ${parsed['matchId']}');
      })

      // 소켓 에러
      ..on('ERROR', (data) {
        debugPrint('[Socket] 서버 에러: $data');
      });
  }

  /// 채팅방 입장
  void joinRoom(String roomId) {
    _activeRoomId = roomId;
    _joinedRooms.remove(roomId); // 새 입장 시도 — ack 를 다시 받아야 한다.
    if (!_isConnected) {
      // 연결 후 onConnect 핸들러가 _activeRoomId 를 자동 재입장한다.
      unawaited(_ensureConnected());
      return;
    }
    _emitJoinRoomWithRetry(roomId, 0);
  }

  /// JOIN_ROOM emit 후 ROOM_JOINED ack 를 500ms 내 못 받으면 재시도(최대 5회).
  /// 재연결 직후 첫 emit 이 transport 미준비로 유실되는 것을 보정한다.
  void _emitJoinRoomWithRetry(String roomId, int attempt) {
    if (attempt >= 5) {
      debugPrint('[Socket] JOIN_ROOM 재시도 한계 도달 — $roomId');
      return;
    }
    if (_joinedRooms.contains(roomId)) return; // 이미 ack 받음
    if (!_isConnected || _activeRoomId != roomId) return; // 끊김/다른 방 이동
    _socket?.emit('JOIN_ROOM', {'roomId': roomId});
    debugPrint('[Socket] JOIN_ROOM emit (시도 ${attempt + 1}): $roomId');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_joinedRooms.contains(roomId)) {
        _emitJoinRoomWithRetry(roomId, attempt + 1);
      }
    });
  }

  /// 채팅방 퇴장
  void leaveRoom(String roomId) {
    if (_activeRoomId == roomId) {
      _activeRoomId = null;
    }
    if (!_isConnected) return;
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
  /// 연결 전이라도 추적 set 에 등록하여, 연결 직후 자동 입장된다.
  void joinMatchRequest(String requestId) {
    _activeMatchRequestRooms.add(requestId);
    if (!_isConnected) {
      // 연결 후 onConnect 핸들러가 _activeMatchRequestRooms 를 자동 재입장한다.
      unawaited(_ensureConnected());
      return;
    }
    _socket!.emit('JOIN_MATCH_REQUEST', {'requestId': requestId});
    debugPrint('[Socket] 매칭 요청 룸 입장: $requestId');
  }

  /// 매칭 요청 룸 퇴장
  void leaveMatchRequest(String requestId) {
    _activeMatchRequestRooms.remove(requestId);
    if (!_isConnected) return;
    _socket!.emit('LEAVE_MATCH_REQUEST', {'requestId': requestId});
    debugPrint('[Socket] 매칭 요청 룸 퇴장: $requestId');
  }

  /// 매칭 룸 입장 (매칭 상태 변경 알림 수신용)
  /// 연결 전이라도 추적 set 에 등록하여, 연결 직후 자동 입장된다.
  void joinMatch(String matchId) {
    _activeMatchRooms.add(matchId);
    if (!_isConnected) {
      // 연결 후 onConnect 핸들러가 _activeMatchRooms 를 자동 재입장한다.
      unawaited(_ensureConnected());
      return;
    }
    _socket!.emit('JOIN_MATCH', {'matchId': matchId});
    debugPrint('[Socket] 매칭 룸 입장: $matchId');
  }

  /// 매칭 룸 퇴장
  void leaveMatch(String matchId) {
    _activeMatchRooms.remove(matchId);
    if (!_isConnected) return;
    _socket!.emit('LEAVE_MATCH', {'matchId': matchId});
    debugPrint('[Socket] 매칭 룸 퇴장: $matchId');
  }

  /// 추적 중인 룸이 하나라도 있는지 (소켓 연결 유지 판단용)
  bool get hasActiveRooms =>
      _activeRoomId != null ||
      _activeMatchRequestRooms.isNotEmpty ||
      _activeMatchRooms.isNotEmpty;

  /// 연결 해제 (로그아웃 시 호출)
  void disconnect() {
    _activeMatchRequestRooms.clear();
    _activeMatchRooms.clear();
    _disconnect();
    _connecting = false;
    _currentAccessToken = null;
    _activeRoomId = null;
    // _disconnect() 가 소켓을 dispose 하면 onDisconnect 핸들러가 누락될 수 있으므로
    // 구독자(chat_provider 등)에게 끊김을 명시적으로 통지한다.
    _connectionStateController.add(false);
  }

  void _disconnect() {
    if (_socket != null) {
      // clearListeners() 는 socket.io 의 공유 Manager 내부 상태를 망가뜨려
      // 이후 새 소켓의 emit 이 전송되지 않는 문제가 있어 사용하지 않는다.
      // 재연결 루프는 connect() 의 _connecting 가드가 막는다.
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
