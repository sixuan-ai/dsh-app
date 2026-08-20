/// System notifications: new private messages and agent events that need
/// attention (approvals, questions). Fires while the app process is alive —
/// including backgrounded; killed-process push would need FCM/OEM channels.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// App-wide notification facade over flutter_local_notifications.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _messagesChannel = AndroidNotificationChannel(
    'messages',
    '私聊消息',
    description: '好友私聊新消息',
    importance: Importance.high,
  );
  static const _agentChannel = AndroidNotificationChannel(
    'agent',
    '助手通知',
    description: '审批请求、提问等需要处理的事件',
    importance: Importance.high,
  );

  /// Initializes the plugin, creates channels, and requests the Android 13+
  /// runtime permission.
  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_messagesChannel);
    await android?.createNotificationChannel(_agentChannel);
    await android?.requestNotificationsPermission();
  }

  Future<void> _show(
      int id, AndroidNotificationChannel channel, String title, String body) {
    return _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// New private message from [peer] (nickname); one notification slot per
  /// peer, so rapid messages update in place.
  Future<void> showMessage(String peer, String nickname, String text) {
    final excerpt = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    return _show(
        1000 + peer.hashCode.abs() % 100000, _messagesChannel, nickname, excerpt);
  }

  /// An approval request needs a decision.
  Future<void> showApproval(String toolName) {
    return _show(2000, _agentChannel, '审批请求', '工具 $toolName 等待你的批准');
  }

  /// An ask-user question batch needs answers.
  Future<void> showQuestion() {
    return _show(2001, _agentChannel, '助手提问', '有问题等待你回答');
  }

  /// A new incoming friend request.
  Future<void> showFriendRequest(String nickname) {
    return _show(2002, _agentChannel, '好友申请', '$nickname 请求添加你为好友');
  }
}
