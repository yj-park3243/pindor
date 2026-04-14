import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../config/theme.dart';

/// 티어별 아이콘
IconData tierIcon(String tier) {
  switch (tier.toUpperCase()) {
    case 'GRANDMASTER':
      return Symbols.local_fire_department_rounded;
    case 'MASTER':
      return Symbols.diamond_rounded;
    case 'PLATINUM':
      return Symbols.auto_awesome_rounded;
    case 'GOLD':
      return Symbols.emoji_events_rounded;
    case 'SILVER':
      return Symbols.shield_rounded;
    case 'BRONZE':
      return Symbols.shield_rounded;
    case 'IRON':
      return Symbols.hexagon_rounded;
    default:
      return Symbols.hexagon_rounded;
  }
}

/// 약어 배지 (리스트, 닉네임 옆 등 — 가장 작은 사이즈)
///
/// ```dart
/// TierBadge(tier: 'GOLD')  // → [GD] 금색 배지
/// ```
class TierBadge extends StatelessWidget {
  final String tier;

  const TierBadge({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tierColor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.35), width: 0.5),
      ),
      child: Text(
        AppTheme.tierShort(tier),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 텍스트 배지 (카드, 프로필 등 — 중간 사이즈)
///
/// ```dart
/// TierBadgeLabel(tier: 'GOLD')  // → [● 골드] 금색 칩
/// ```
class TierBadgeLabel extends StatelessWidget {
  final String tier;

  const TierBadgeLabel({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tierColor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            AppTheme.tierName(tier),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 아이콘 배지 (프로필 헤더, 결과 화면 등 — 큰 사이즈)
///
/// ```dart
/// TierBadgeIcon(tier: 'GOLD')  // → [🏆 골드] 금색 그라데이션 칩
/// ```
class TierBadgeIcon extends StatelessWidget {
  final String tier;

  const TierBadgeIcon({super.key, required this.tier});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tierColor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tierIcon(tier), size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            AppTheme.tierName(tier),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 인라인 점 + 한글명 (텍스트 사이에 끼워넣기용)
///
/// ```dart
/// TierDot(tier: 'GOLD')  // → ● 골드
/// ```
class TierDot extends StatelessWidget {
  final String tier;
  final double fontSize;

  const TierDot({super.key, required this.tier, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tierColor(tier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          AppTheme.tierName(tier),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
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
            child: Icon(tierIcon(tier), color: color, size: 42),
          ),
        ),
        const SizedBox(height: 10),
        TierBadgeIcon(tier: tier),
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
}
