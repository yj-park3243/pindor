import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 티어 배지 위젯
/// 크기별: small(18px), medium(28px), large(52px)
/// showLabel: true 시 텍스트 레이블 포함
class TierBadge extends StatelessWidget {
  final String tier;
  final double size;
  final bool showLabel;

  const TierBadge({
    super.key,
    required this.tier,
    this.size = 28,
    this.showLabel = false,
  });

  /// 소형 (리스트 등) - 18px
  const TierBadge.small({
    super.key,
    required this.tier,
    this.showLabel = false,
  }) : size = 18;

  /// 중형 (카드 등) - 28px
  const TierBadge.medium({
    super.key,
    required this.tier,
    this.showLabel = false,
  }) : size = 28;

  /// 대형 (프로필 헤더) - 52px
  const TierBadge.large({
    super.key,
    required this.tier,
    this.showLabel = false,
  }) : size = 52;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tierColor(tier);
    final icon = _tierIcon(tier);
    final label = _tierLabel(tier);

    if (showLabel) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: size * 0.45,
          vertical: size * 0.2,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.6), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: size * 0.55),
            SizedBox(width: size * 0.2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.45,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.6), width: 1.5),
      ),
      child: Center(
        child: Icon(icon, color: color, size: size * 0.55),
      ),
    );
  }

  IconData _tierIcon(String tier) {
    switch (tier.toUpperCase()) {
      case 'GRANDMASTER':
        return Icons.workspace_premium_rounded; // 왕관
      case 'MASTER':
        return Icons.diamond_rounded; // 다이아몬드
      case 'PLATINUM':
        return Icons.star_rounded; // 별
      case 'GOLD':
        return Icons.shield_rounded; // 실드
      case 'SILVER':
        return Icons.shield; // 실드
      case 'BRONZE':
        return Icons.shield_outlined; // 실드
      case 'IRON':
        return Icons.circle_outlined; // 원형
      default:
        return Icons.circle_outlined;
    }
  }

  String _tierLabel(String tier) {
    switch (tier.toUpperCase()) {
      case 'GRANDMASTER':
        return '그랜드마스터';
      case 'MASTER':
        return '마스터';
      case 'PLATINUM':
        return '플래티넘';
      case 'GOLD':
        return '골드';
      case 'SILVER':
        return '실버';
      case 'BRONZE':
        return '브론즈';
      case 'IRON':
        return '아이언';
      default:
        return tier;
    }
  }
}

/// 대형 티어 배지 (결과 화면용)
class LargeTierBadge extends StatelessWidget {
  final String tier;
  final int score;

  const LargeTierBadge({
    super.key,
    required this.tier,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tierColor(tier);

    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [color.withOpacity(0.3), color.withOpacity(0.08)],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: _buildTierIcon(tier, color),
          ),
        ),
        const SizedBox(height: 10),
        TierBadge(tier: tier, showLabel: true, size: 24),
        const SizedBox(height: 4),
        Text(
          '$score점',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTierIcon(String tier, Color color) {
    switch (tier.toUpperCase()) {
      case 'GRANDMASTER':
        return Icon(Icons.workspace_premium_rounded, color: color, size: 42);
      case 'MASTER':
        return Icon(Icons.diamond_rounded, color: color, size: 42);
      case 'PLATINUM':
        return Icon(Icons.star_rounded, color: color, size: 42);
      case 'GOLD':
        return Icon(Icons.shield_rounded, color: color, size: 42);
      case 'SILVER':
        return Icon(Icons.shield, color: color, size: 42);
      case 'BRONZE':
        return Icon(Icons.shield_outlined, color: color, size: 42);
      case 'IRON':
        return Icon(Icons.circle_outlined, color: color, size: 42);
      default:
        return Icon(Icons.circle_outlined, color: color, size: 42);
    }
  }
}
