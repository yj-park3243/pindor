import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/ranking_entry.dart';
import '../common/user_avatar.dart';

/// 랭킹 리스트 아이템 위젯
class RankingListTile extends StatelessWidget {
  final RankingEntry entry;
  final bool isMe;
  final VoidCallback? onTap;

  const RankingListTile({
    super.key,
    required this.entry,
    this.isMe = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.primaryColor.withOpacity(0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? AppTheme.primaryColor.withOpacity(0.3)
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RankNumber(rank: entry.rank),
            const SizedBox(width: 12),
            UserAvatar(
              imageUrl: entry.profileImageUrl,
              size: 44,
              nickname: entry.nickname,
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.nickname,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: isMe ? AppTheme.primaryColor : AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isMe)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ME',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${entry.gamesPlayed}경기 · ${entry.wins}승 ${entry.losses}패',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${entry.score}점',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankNumber extends StatelessWidget {
  final int rank;

  const _RankNumber({required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank <= 3) {
      final colors = [
        const Color(0xFFFFD700), // 1위 금
        const Color(0xFFC0C0C0), // 2위 은
        const Color(0xFFCD7F32), // 3위 동
      ];
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: colors[rank - 1],
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$rank',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 28,
      child: Text(
        '$rank',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
