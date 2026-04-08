import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 배치 게임 여부에 따라 점수 또는 "배치 중 (N/5)" 뱃지를 표시하는 위젯.
///
/// - [isPlacement] == true  → 오렌지 뱃지로 "배치 중 (N/5)" 표시
/// - [isPlacement] == false → "${score}점" 텍스트 표시
class ScoreText extends StatelessWidget {
  final int score;
  final bool isPlacement;
  final int? placementGamesRemaining;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;

  const ScoreText({
    super.key,
    required this.score,
    this.isPlacement = false,
    this.placementGamesRemaining,
    this.fontSize = 16,
    this.fontWeight = FontWeight.w700,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (isPlacement) {
      final played = 5 - (placementGamesRemaining ?? 5);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Text(
          '배치 중 ($played/5)',
          style: TextStyle(
            fontSize: fontSize * 0.85,
            fontWeight: fontWeight,
            color: Colors.orange.shade700,
          ),
        ),
      );
    }
    return Text(
      '$score점',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppTheme.primaryColor,
      ),
    );
  }
}

/// 점수 표시 위젯
/// 큰 점수 + 변동 화살표 (▲/▼)
class ScoreDisplay extends StatelessWidget {
  final int score;
  final String? tier; // 서버 호환용으로 파라미터는 유지하나 UI에는 사용하지 않음
  final int? delta; // 점수 변동 (+28, -15 등)
  final bool large;

  const ScoreDisplay({
    super.key,
    required this.score,
    this.tier,
    this.delta,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          score.toString(),
          style: TextStyle(
            fontSize: large ? 36 : 20,
            fontWeight: FontWeight.w900,
            color: AppTheme.primaryColor,
            letterSpacing: large ? -1 : 0,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '점',
            style: TextStyle(
              fontSize: large ? 16 : 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor.withOpacity(0.7),
            ),
          ),
        ),
        if (delta != null) ...[
          const SizedBox(width: 6),
          _ScoreDeltaBadge(delta: delta!),
        ],
      ],
    );
  }
}

class _ScoreDeltaBadge extends StatelessWidget {
  final int delta;

  const _ScoreDeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final isPositive = delta > 0;
    final isZero = delta == 0;
    final color = isZero
        ? AppTheme.textSecondary
        : isPositive
            ? AppTheme.secondaryColor
            : AppTheme.errorColor;
    final sign = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isZero)
            Icon(
              isPositive
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              size: 16,
              color: color,
            ),
          Text(
            isZero ? '±0' : '$sign$delta',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 점수 변동 애니메이션 위젯 (결과 화면용)
class AnimatedScoreCounter extends StatefulWidget {
  final int fromScore;
  final int toScore;
  final String? tier; // 서버 호환용으로 파라미터는 유지하나 UI에는 사용하지 않음
  final Duration duration;

  const AnimatedScoreCounter({
    super.key,
    required this.fromScore,
    required this.toScore,
    this.tier,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<AnimatedScoreCounter> createState() =>
      _AnimatedScoreCounterState();
}

class _AnimatedScoreCounterState extends State<AnimatedScoreCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delta = widget.toScore - widget.fromScore;
    final isPositive = delta > 0;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final currentScore = (widget.fromScore +
                (widget.toScore - widget.fromScore) * _animation.value)
            .round();

        return Column(
          children: [
            // 점수 숫자
            Text(
              '$currentScore',
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryColor,
                letterSpacing: -2,
              ),
            ),
            Text(
              '점',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor.withOpacity(0.7),
              ),
            ),
            // 점수 변동 배지 (애니메이션 후반에 등장)
            if (_animation.value > 0.5 && delta != 0) ...[
              const SizedBox(height: 8),
              AnimatedOpacity(
                opacity: ((_animation.value - 0.5) * 2).clamp(0.0, 1.0),
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isPositive
                            ? AppTheme.secondaryColor
                            : AppTheme.errorColor)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                        color: isPositive
                            ? AppTheme.secondaryColor
                            : AppTheme.errorColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${isPositive ? '+' : ''}$delta점',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isPositive
                              ? AppTheme.secondaryColor
                              : AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
