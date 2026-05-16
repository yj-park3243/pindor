import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../core/dev/debug_log_buffer.dart';
import '../../core/dev/last_sync_stats.dart';
import '../../core/network/socket_service.dart';
import '../../core/version/version_check_service.dart';
import '../../data/local/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/native_ad_card.dart';

const _kBuildTime =
    String.fromEnvironment('BUILD_TIME', defaultValue: 'unknown');

/// 숨겨진 개발자 메뉴. 마이페이지 → 설정 → "앱 버전" 20번 탭으로 진입.
class AdTestScreen extends ConsumerStatefulWidget {
  const AdTestScreen({super.key});

  @override
  ConsumerState<AdTestScreen> createState() => _AdTestScreenState();
}

class _AdTestScreenState extends ConsumerState<AdTestScreen> {
  PackageInfo? _pkg;
  String? _fcmToken;
  String? _notifPerm;
  int? _localChatRooms;
  int? _localMessages;
  int? _localMatches;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pkg = await PackageInfo.fromPlatform();
    String? fcm;
    String? perm;
    try {
      fcm = await FirebaseMessaging.instance.getToken();
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      perm = settings.authorizationStatus.name;
    } catch (_) {}

    int? rooms;
    int? messages;
    int? matches;
    try {
      final db = ref.read(appDatabaseProvider);
      rooms = await db.chatDao.getChatRoomCount();
      messages = await db.chatDao.getTotalMessageCount();
      matches = await db.matchesDao.getMatchCount();
    } catch (e) {
      debugPrint('[DevMenu] local count 조회 실패: $e');
    }

    if (!mounted) return;
    setState(() {
      _pkg = pkg;
      _fcmToken = fcm;
      _notifPerm = perm;
      _localChatRooms = rooms;
      _localMessages = messages;
      _localMatches = matches;
    });
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success('$label 복사됨');
  }

  String _env() {
    if (AppConfig.isDevelopment) return 'development';
    if (AppConfig.isProduction) return 'production';
    return 'unknown';
  }

  String _buildMode() {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    if (kDebugMode) return 'debug';
    return 'unknown';
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final t = dt.toLocal();
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
  }

  String _buildAllInfo() {
    final user = ref.read(currentUserProvider);
    final socket = SocketService.instance;
    return '''
[APP]
version: ${_pkg?.version ?? '-'}+${_pkg?.buildNumber ?? '-'}
env: ${_env()}
buildMode: ${_buildMode()}
buildTime: $_kBuildTime
package: ${_pkg?.packageName ?? '-'}
apiBase: ${AppConfig.apiBaseUrl}
socketUrl: ${AppConfig.socketUrl}

[VERSION CHECK]
minVersion: ${VersionCheckService.lastMinVersion ?? '-'}
latestVersion: ${VersionCheckService.lastLatestVersion ?? '-'}
forceUpdate: ${VersionCheckService.lastForceUpdate}
lastCheckedAt: ${_fmt(VersionCheckService.lastCheckedAt)}
showAd: ${VersionCheckService.showAd}
requirePhoneVerification: ${VersionCheckService.requirePhoneVerification}

[USER]
id: ${user?.id ?? '-'}
nickname: ${user?.nickname ?? '-'}
email: ${user?.email ?? '-'}

[SOCKET]
connected: ${socket.isConnected}
activeRoomId: ${socket.activeRoomId ?? '-'}

[FCM]
permission: ${_notifPerm ?? '-'}
token: $_fcmToken

[DATA]
localChatRooms: $_localChatRooms
localMessages: $_localMessages
localMatches: $_localMatches
lastSync.chatRooms: ${_fmt(LastSyncStats.get('chatRooms'))}
lastSync.matches: ${_fmt(LastSyncStats.get('matches'))}

[SYSTEM]
platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
dart: ${Platform.version.split(' ').first}
''';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: AppBar(
          title: const Text('개발자 메뉴'),
          backgroundColor: AppTheme.backgroundLight,
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: '전체 정보 복사',
              onPressed: () => _copy(_buildAllInfo(), '전체 정보'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '새로고침',
              onPressed: _load,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '앱'),
              Tab(text: '사용자'),
              Tab(text: '데이터'),
              Tab(text: '로그'),
              Tab(text: '광고'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AppTab(
              pkg: _pkg,
              env: _env(),
              buildMode: _buildMode(),
              buildTime: _kBuildTime,
              fmt: _fmt,
              copy: _copy,
            ),
            _UserTab(notifPerm: _notifPerm, fcmToken: _fcmToken, copy: _copy),
            _DataTab(
              chatRooms: _localChatRooms,
              messages: _localMessages,
              matches: _localMatches,
              fmt: _fmt,
            ),
            const _LogsTab(),
            const _AdTab(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 탭 1: 앱
// ─────────────────────────────────────────────
class _AppTab extends StatelessWidget {
  final PackageInfo? pkg;
  final String env;
  final String buildMode;
  final String buildTime;
  final String Function(DateTime?) fmt;
  final void Function(String, String) copy;

  const _AppTab({
    required this.pkg,
    required this.env,
    required this.buildMode,
    required this.buildTime,
    required this.fmt,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final version = '${pkg?.version ?? '-'}+${pkg?.buildNumber ?? '-'}';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Section(title: '앱 정보', rows: [
          _InfoRow(label: '버전', value: version, onCopy: () => copy(version, '버전')),
          _InfoRow(label: '환경', value: env),
          _InfoRow(label: '빌드 모드', value: buildMode),
          _InfoRow(label: '빌드 일시', value: buildTime),
          _InfoRow(label: '패키지', value: pkg?.packageName ?? '-'),
        ]),
        _Section(title: '네트워크', rows: [
          _InfoRow(
            label: 'API',
            value: AppConfig.apiBaseUrl,
            onCopy: () => copy(AppConfig.apiBaseUrl, 'API URL'),
          ),
          _InfoRow(label: 'Socket', value: AppConfig.socketUrl),
        ]),
        _Section(title: 'Version Check (원격 토글)', rows: [
          _InfoRow(label: 'minVersion', value: VersionCheckService.lastMinVersion ?? '-'),
          _InfoRow(label: 'latestVersion', value: VersionCheckService.lastLatestVersion ?? '-'),
          _InfoRow(label: 'forceUpdate', value: '${VersionCheckService.lastForceUpdate}'),
          _InfoRow(label: 'lastCheckedAt', value: fmt(VersionCheckService.lastCheckedAt)),
          _InfoRow(label: 'showAd', value: '${VersionCheckService.showAd}'),
          _InfoRow(label: 'requirePhone', value: '${VersionCheckService.requirePhoneVerification}'),
        ]),
        _Section(title: '시스템', rows: [
          _InfoRow(
            label: 'Platform',
            value: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          ),
          _InfoRow(label: 'Dart', value: Platform.version.split(' ').first),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 탭 2: 사용자
// ─────────────────────────────────────────────
class _UserTab extends ConsumerWidget {
  final String? notifPerm;
  final String? fcmToken;
  final void Function(String, String) copy;

  const _UserTab({
    required this.notifPerm,
    required this.fcmToken,
    required this.copy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final socket = SocketService.instance;
    final tokenPreview = fcmToken == null
        ? '(로딩 중)'
        : '${fcmToken!.substring(0, fcmToken!.length.clamp(0, 32))}…';
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Section(title: '현재 사용자', rows: [
          _InfoRow(
            label: 'User ID',
            value: user?.id ?? '-',
            onCopy: user?.id == null ? null : () => copy(user!.id, 'User ID'),
          ),
          _InfoRow(label: '닉네임', value: user?.nickname ?? '-'),
          _InfoRow(label: '이메일', value: user?.email ?? '-'),
        ]),
        _Section(title: '소켓', rows: [
          _InfoRow(
            label: '연결',
            value: socket.isConnected ? 'connected' : 'disconnected',
          ),
          _InfoRow(label: 'Active Room', value: socket.activeRoomId ?? '-'),
        ]),
        _Section(title: 'FCM', rows: [
          _InfoRow(label: '권한', value: notifPerm ?? '-'),
          _InfoRow(
            label: 'Token',
            value: tokenPreview,
            onCopy: fcmToken == null ? null : () => copy(fcmToken!, 'FCM 토큰'),
          ),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 탭 3: 데이터
// ─────────────────────────────────────────────
class _DataTab extends StatelessWidget {
  final int? chatRooms;
  final int? messages;
  final int? matches;
  final String Function(DateTime?) fmt;

  const _DataTab({
    required this.chatRooms,
    required this.messages,
    required this.matches,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Section(title: '로컬 캐시 (Drift)', rows: [
          _InfoRow(label: '채팅방', value: '${chatRooms ?? '-'} 개'),
          _InfoRow(label: '메시지', value: '${messages ?? '-'} 개'),
          _InfoRow(label: '매칭', value: '${matches ?? '-'} 개'),
        ]),
        _Section(title: '마지막 서버 동기화', rows: [
          _InfoRow(label: 'chatRooms', value: fmt(LastSyncStats.get('chatRooms'))),
          _InfoRow(label: 'matches', value: fmt(LastSyncStats.get('matches'))),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 탭 4: 로그 (in-memory ring buffer)
// ─────────────────────────────────────────────
class _LogsTab extends StatefulWidget {
  const _LogsTab();

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  late List<DebugLogEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = DebugLogBuffer.instance.snapshot;
    DebugLogBuffer.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _entries = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1E1E1E),
          child: Row(
            children: [
              Text(
                '${_entries.length} 줄',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('전체 복사'),
                onPressed: () {
                  final text = _entries
                      .map((e) =>
                          '${e.time.toIso8601String()} ${e.message}')
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  AppToast.success('로그 ${_entries.length}줄 복사됨');
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('지우기'),
                onPressed: () => DebugLogBuffer.instance.clear(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? const Center(
                  child: Text(
                    '로그 없음',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final e = _entries[_entries.length - 1 - index];
                    final t = e.time;
                    final pad = (int n) => n.toString().padLeft(2, '0');
                    final ts = '${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}.${pad(t.millisecond ~/ 10)}';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: SelectableText(
                        '$ts  ${e.message}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.35,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 탭 5: 광고 (기존 NativeAdCard 테스트)
// ─────────────────────────────────────────────
class _AdTab extends StatelessWidget {
  const _AdTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Text(
                'showAd: ${VersionCheckService.showAd}\nOFF면 카드 자체가 렌더링되지 않습니다. admin → 시스템 설정 → 광고에서 ON 후 앱 재실행.',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const NativeAdCard(highlightAdLabel: true),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공통 위젯
// ─────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final List<_InfoRow> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1)
                    const Divider(height: 1, color: Color(0xFF262626)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _InfoRow({required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onCopy != null)
              const Icon(Icons.copy_outlined, size: 14, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
