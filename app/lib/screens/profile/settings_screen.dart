import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';

/// 설정 화면 (PRD SCREEN-064)
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 알림 설정
          _buildSectionHeader('알림'),
          _buildSettingsCard([
            _buildListTile(
              context,
              icon: Icons.notifications_outlined,
              iconColor: AppTheme.primaryColor,
              title: '알림 설정',
              onTap: () =>
                  context.push('/profile/settings/notifications'),
            ),
          ]),

          // 계정
          _buildSectionHeader('계정'),
          _buildSettingsCard([
            _buildListTile(
              context,
              icon: Icons.person_outline_rounded,
              iconColor: AppTheme.primaryColor,
              title: '프로필 수정',
              onTap: () => context.push('/profile/edit'),
            ),
          ]),

          // 정보
          _buildSectionHeader('정보'),
          _buildSettingsCard([
            _buildListTile(
              context,
              icon: Icons.description_outlined,
              iconColor: AppTheme.textSecondary,
              title: '이용 약관',
              onTap: () => _launchUrl('https://pins.kr/terms'),
            ),
            const Divider(height: 1, indent: 56, endIndent: 16),
            _buildListTile(
              context,
              icon: Icons.privacy_tip_outlined,
              iconColor: AppTheme.textSecondary,
              title: '개인정보 처리방침',
              onTap: () => _launchUrl('https://pins.kr/privacy'),
            ),
            const Divider(height: 1, indent: 56, endIndent: 16),
            _buildListTile(
              context,
              icon: Icons.info_outline_rounded,
              iconColor: AppTheme.textSecondary,
              title: '앱 버전',
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '1.0.0',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              onTap: null,
            ),
          ]),

          const SizedBox(height: 8),

          // 계정 관련
          _buildSectionHeader(''),
          _buildSettingsCard([
            _buildListTile(
              context,
              icon: Icons.logout_rounded,
              iconColor: AppTheme.errorColor,
              title: '로그아웃',
              titleColor: AppTheme.errorColor,
              onTap: () => _showLogoutDialog(context, ref),
            ),
            const Divider(height: 1, indent: 56, endIndent: 16),
            _buildListTile(
              context,
              icon: Icons.person_remove_outlined,
              iconColor: AppTheme.textDisabled,
              title: '회원 탈퇴',
              titleColor: AppTheme.textDisabled,
              onTap: () => _showWithdrawDialog(context, ref),
            ),
          ]),

          const SizedBox(height: 40),

          // 앱 정보 (하단)
          const Center(
            child: Text(
              '핀돌 v1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textDisabled,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              '내 근처 스포츠 대결 매칭',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textDisabled,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: title.isEmpty
          ? const SizedBox(height: 4)
          : Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? AppTheme.textSecondary).withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor ?? AppTheme.textSecondary,
          size: 18,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: titleColor,
        ),
      ),
      trailing: trailing ??
          (onTap != null
              ? const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textDisabled,
                  size: 20,
                )
              : null),
      onTap: onTap,
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showLogoutDialog(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.errorColor,
            ),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(authStateProvider.notifier).logout();
      if (context.mounted) {
        context.go(AppRoutes.login);
      }
    }
  }

  Future<void> _showWithdrawDialog(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '정말로 탈퇴하시겠습니까?\n탈퇴 후 모든 데이터가 삭제되며\n복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.errorColor,
            ),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(authStateProvider.notifier).deleteAccount();
        if (context.mounted) {
          context.go(AppRoutes.login);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다: $e')),
          );
        }
      }
    }
  }
}
