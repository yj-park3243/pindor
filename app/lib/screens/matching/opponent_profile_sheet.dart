import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../widgets/common/user_avatar.dart';

/// 상대 프로필 바텀시트 (PRD SCREEN-024)
class OpponentProfileSheet extends StatelessWidget {
  final MatchOpponent opponent;

  const OpponentProfileSheet({super.key, required this.opponent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // 프로필 이미지
          UserAvatar(
            imageUrl: opponent.profileImageUrl,
            size: 80,
            nickname: opponent.nickname,
          ),
          const SizedBox(height: 16),

          Text(
            opponent.nickname,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 20),

          // 총 경기
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: '총 경기',
                  value: '${opponent.gamesPlayed}',
                  unit: '게임',
                ),
              ),
            ],
          ),

          // G핸디 (골프)
          if (opponent.sportType == 'GOLF' && opponent.gHandicap != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '골프존 G핸디',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  Text(
                    '${opponent.gHandicap}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // 닫기
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: (color ?? const Color(0xFF9CA3AF)).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
