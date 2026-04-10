import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/notification.dart';
import '../../repositories/notification_repository.dart';
import '../../widgets/common/app_toast.dart';

/// 알림 ON/OFF 설정 화면 (PRD SCREEN-065)
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationSettings _settings = const NotificationSettings();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final repo = ref.read(notificationRepositoryProvider);
      final settings = await repo.getSettings();
      setState(() {
        _settings = settings;
      });
    } catch (_) {
      // 실패 시 기본값 유지
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final repo = ref.read(notificationRepositoryProvider);
      await repo.updateSettings(_settings);
      if (mounted) {
        AppToast.success('알림 설정이 저장되었습니다.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('저장에 실패했습니다: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 설정'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '저장',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildSectionHeader('경기 알림'),
          _buildSwitchTile(
            title: '게임 결과',
            subtitle: '결과 입력/인증 시 알림을 받습니다',
            value: _settings.gameResult,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(gameResult: v)),
          ),
          _buildSwitchTile(
            title: '점수 변동',
            subtitle: '점수가 변경되면 알림을 받습니다',
            value: _settings.scoreChange,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(scoreChange: v)),
          ),

          _buildSectionHeader('메시지 알림'),
          _buildSwitchTile(
            title: '채팅 메시지',
            subtitle: '새 채팅 메시지가 오면 알림을 받습니다',
            value: _settings.chatMessage,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(chatMessage: v)),
          ),

          _buildSectionHeader('커뮤니티 알림'),
          _buildSwitchTile(
            title: '댓글 알림',
            subtitle: '내 게시글/댓글에 답글이 달리면 알림을 받습니다',
            value: _settings.communityReply,
            onChanged: (v) => setState(
                () => _settings = _settings.copyWith(communityReply: v)),
          ),

          _buildSectionHeader('방해 금지'),
          _buildDoNotDisturbTile(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primaryColor,
    );
  }

  Widget _buildDoNotDisturbTile() {
    final hasSchedule = _settings.doNotDisturbStart != null &&
        _settings.doNotDisturbEnd != null;

    return Column(
      children: [
        SwitchListTile(
          title: const Text('방해 금지 시간', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            hasSchedule
                ? '${_settings.doNotDisturbStart} ~ ${_settings.doNotDisturbEnd}'
                : '특정 시간대에 알림을 받지 않습니다',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          value: hasSchedule,
          onChanged: (v) {
            if (v) {
              setState(() {
                _settings = _settings.copyWith(
                  doNotDisturbStart: '23:00',
                  doNotDisturbEnd: '08:00',
                );
              });
            } else {
              setState(() {
                _settings = NotificationSettings(
                  chatMessage: _settings.chatMessage,
                  matchFound: _settings.matchFound,
                  matchRequest: _settings.matchRequest,
                  gameResult: _settings.gameResult,
                  scoreChange: _settings.scoreChange,
                  communityReply: _settings.communityReply,
                );
              });
            }
          },
          activeColor: AppTheme.primaryColor,
        ),
        if (hasSchedule)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _TimePickerButton(
                    label: '시작 시간',
                    time: _settings.doNotDisturbStart ?? '23:00',
                    onPick: (time) => setState(
                      () => _settings =
                          _settings.copyWith(doNotDisturbStart: time),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('~', style: TextStyle(fontSize: 18)),
                ),
                Expanded(
                  child: _TimePickerButton(
                    label: '종료 시간',
                    time: _settings.doNotDisturbEnd ?? '08:00',
                    onPick: (time) => setState(
                      () =>
                          _settings = _settings.copyWith(doNotDisturbEnd: time),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  final String label;
  final String time;
  final void Function(String) onPick;

  const _TimePickerButton({
    required this.label,
    required this.time,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final parts = time.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 23,
          minute: int.tryParse(parts[1]) ?? 0,
        );
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (picked != null) {
          final formatted =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          onPick(formatted);
        }
      },
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
