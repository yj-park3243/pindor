import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 디자이너 PINDOR 시안 기반 종목 배지
/// - 원형 그라데이션 배경 (tokens.js sport colors 기반)
/// - 선택(selected)되면 강한 그라데이션 + 글로우
/// - 비선택은 배경 opacity 낮춰서 은은하게
class SportBadge extends StatelessWidget {
  final String sportValue;
  final IconData icon;
  final double size;
  final bool selected;

  const SportBadge({
    super.key,
    required this.sportValue,
    required this.icon,
    this.size = 56,
    this.selected = true,
  });

  @override
  Widget build(BuildContext context) {
    final grad = AppTheme.sportGradient(sportValue);
    final c1 = grad.first;
    final c2 = grad.last;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? [c1, c2]
              : [c1.withValues(alpha: 0.22), c2.withValues(alpha: 0.22)],
        ),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.35)
              : c1.withValues(alpha: 0.4),
          width: selected ? 1.8 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: c1.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.5,
          color: selected ? Colors.white : c1,
        ),
      ),
    );
  }
}

/// 매칭 상태 칩 (시안 StateChip 모티브)
class MatchStateChip extends StatelessWidget {
  final String status;

  const MatchStateChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _statusMeta(String status) {
    switch (status) {
      case 'PENDING_ACCEPT':
        return (AppTheme.statePendingAccept, '수락 대기');
      case 'CHAT':
      case 'CONFIRMED':
        return (AppTheme.stateAccepted, '매칭 성사');
      case 'COMPLETED':
        return (AppTheme.stateCompleted, '완료');
      case 'CANCELLED':
        return (AppTheme.stateCanceled, '취소');
      case 'DISPUTED':
        return (AppTheme.stateDisputed, '분쟁');
      default:
        return (AppTheme.stateSearching, status);
    }
  }
}
