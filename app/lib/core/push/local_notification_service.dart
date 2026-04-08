import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// 로컬 알림 서비스 (PRD 4.10.10 Android 채널 설정 기반)
/// - Android 8.0+ 알림 채널 설정
/// - 포그라운드 알림 표시
/// - 인앱 배너 알림 연동
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService _instance =
      LocalNotificationService._();
  static LocalNotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // 알림 탭 콜백
  void Function(String? payload)? onNotificationTap;

  // ─── Android 알림 채널 정의 (PRD 4.10.10) ───
  static const AndroidNotificationChannel matchAlertsChannel =
      AndroidNotificationChannel(
    'match_alerts',
    '매칭 알림',
    description: '매칭 성사, 요청, 수락/거절 알림',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel chatMessagesChannel =
      AndroidNotificationChannel(
    'chat_messages',
    '채팅 메시지',
    description: '새 채팅 메시지 알림',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel generalChannel =
      AndroidNotificationChannel(
    'general',
    '일반 알림',
    description: '점수 변동, 결과 인증, 커뮤니티 알림',
    importance: Importance.defaultImportance,
  );

  /// 초기화
  Future<void> initialize() async {
    // Android 채널 생성
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(matchAlertsChannel);
    await androidPlugin?.createNotificationChannel(chatMessagesChannel);
    await androidPlugin?.createNotificationChannel(generalChannel);

    // 초기화 설정
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        onNotificationTap?.call(details.payload);
      },
    );

    debugPrint('[LocalNotification] 초기화 완료');
  }

  /// FCM 원격 메시지로부터 로컬 알림 표시
  Future<void> showFromRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final channel = _getChannelForType(message.data['type'] as String?);

    await _plugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel.importance == Importance.high
              ? Priority.high
              : Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['deepLink'] as String?,
    );
  }

  /// 인앱 알림 (일반 텍스트)
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = 'general',
  }) async {
    final channelName = channelId == 'match_alerts'
        ? '매칭 알림'
        : channelId == 'chat_messages'
            ? '채팅 메시지'
            : '일반 알림';

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// 알림 유형에 맞는 채널 반환
  AndroidNotificationChannel _getChannelForType(String? type) {
    switch (type) {
      case 'MATCH_FOUND':
      case 'MATCH_REQUEST_RECEIVED':
      case 'MATCH_ACCEPTED':
      case 'MATCH_REJECTED':
      case 'MATCH_EXPIRED':
        return matchAlertsChannel;
      case 'CHAT_MESSAGE':
      case 'CHAT_IMAGE':
        return chatMessagesChannel;
      default:
        return generalChannel;
    }
  }

  /// 모든 알림 제거
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
