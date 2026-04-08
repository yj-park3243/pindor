import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../models/team.dart';

/// 팀 멤버 목록 아이템
class TeamMemberTile extends StatelessWidget {
  final TeamMember member;
  final bool showActions;
  final bool isSelf;
  final VoidCallback? onTransferCaptain;
  final VoidCallback? onToggleViceCaptain;
  final VoidCallback? onKick;

  const TeamMemberTile({
    super.key,
    required this.member,
    this.showActions = false,
    this.isSelf = false,
    this.onTransferCaptain,
    this.onToggleViceCaptain,
    this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final nickname = user?.nickname ?? '알 수 없음';
    final profileImage = user?.profileImageUrl;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: profileImage != null
                ? CachedNetworkImageProvider(profileImage)
                : null,
            child: profileImage == null
                ? Text(
                    nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  )
                : null,
          ),
          if (member.isCaptain || member.isViceCaptain)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: member.isCaptain
                      ? const Color(0xFFFFD700)
                      : AppTheme.primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Icon(
                  member.isCaptain ? Icons.star : Icons.star_half,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(
            nickname,
            style: TextStyle(
              fontSize: 15,
              fontWeight:
                  member.isCaptain ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (isSelf) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '나',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          _RoleBadge(role: member.role),
          if (member.position != null) ...[
            const SizedBox(width: 6),
            Text(
              member.position!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
      trailing: showActions && !isSelf
          ? _ActionsMenu(
              member: member,
              onTransferCaptain: onTransferCaptain,
              onToggleViceCaptain: onToggleViceCaptain,
              onKick: onKick,
            )
          : null,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (role) {
      case 'CAPTAIN':
        color = const Color(0xFFFFD700);
        label = '방장';
        break;
      case 'VICE_CAPTAIN':
        color = AppTheme.primaryColor;
        label = '부방장';
        break;
      default:
        color = AppTheme.textSecondary;
        label = '팀원';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color == const Color(0xFFFFD700)
              ? const Color(0xFFB8860B)
              : color,
        ),
      ),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  final TeamMember member;
  final VoidCallback? onTransferCaptain;
  final VoidCallback? onToggleViceCaptain;
  final VoidCallback? onKick;

  const _ActionsMenu({
    required this.member,
    this.onTransferCaptain,
    this.onToggleViceCaptain,
    this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      onSelected: (value) {
        switch (value) {
          case 'transfer':
            onTransferCaptain?.call();
            break;
          case 'vice':
            onToggleViceCaptain?.call();
            break;
          case 'kick':
            onKick?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (onTransferCaptain != null)
          const PopupMenuItem(
            value: 'transfer',
            child: Row(
              children: [
                Icon(Icons.swap_horiz, size: 18, color: Color(0xFFFFD700)),
                SizedBox(width: 8),
                Text('방장 넘기기'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'vice',
          child: Row(
            children: [
              Icon(
                member.isViceCaptain ? Icons.remove_circle_outline : Icons.star_half,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(member.isViceCaptain ? '부방장 해임' : '부방장 임명'),
            ],
          ),
        ),
        if (onKick != null)
          const PopupMenuItem(
            value: 'kick',
            child: Row(
              children: [
                Icon(Icons.person_remove_outlined,
                    size: 18, color: AppTheme.errorColor),
                SizedBox(width: 8),
                Text('추방', style: TextStyle(color: AppTheme.errorColor)),
              ],
            ),
          ),
      ],
    );
  }
}
