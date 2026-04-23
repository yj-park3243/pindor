import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// 전 화면 공통 “은은한 빛” 배경.
/// - 2개의 라디얼 그라데이션 blob이 천천히 궤적을 그리며 이동
/// - seed 값에 따라 초기 위치/색/속도가 달라 화면마다 분위기가 다르게 보임
/// - 비용은 `Container(decoration: RadialGradient)` + 가벼운 `ImageFilter.blur`만 사용
class AmbientGlowBackground extends StatefulWidget {
  final Widget child;
  final int seed;

  /// 전체 톤을 바꾸고 싶을 때 override. 비워두면 orange/amber 계열.
  final Color? color1;
  final Color? color2;

  const AmbientGlowBackground({
    super.key,
    required this.child,
    this.seed = 0,
    this.color1,
    this.color2,
  });

  @override
  State<AmbientGlowBackground> createState() => _AmbientGlowBackgroundState();
}

class _AmbientGlowBackgroundState extends State<AmbientGlowBackground>
    with TickerProviderStateMixin {
  late final AnimationController _a;
  late final AnimationController _b;

  @override
  void initState() {
    super.initState();
    // seed를 초기 phase로 사용 → 같은 화면은 같은 궤적, 다른 화면은 다른 궤적
    final phaseA = (widget.seed % 1000) / 1000.0;
    final phaseB = ((widget.seed * 37 + 13) % 1000) / 1000.0;

    _a = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _b = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();

    // 초기 value로 건너뛰기 (animateTo는 즉시 duration 내 진행이라 value 직접 할당)
    _a.value = phaseA;
    _b.value = phaseB;
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Alignment _lerpCircle(double t, double radius, Alignment center) {
    final angle = t * 2 * math.pi;
    return Alignment(
      center.x + radius * math.cos(angle),
      center.y + radius * math.sin(angle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c1 = widget.color1 ?? const Color(0xFFFFB344); // 따뜻한 앰버
    final c2 = widget.color2 ?? const Color(0xFFFF6B2C); // 프라이머리 오렌지

    return Stack(
      fit: StackFit.expand,
      children: [
        // glow 1 — 위쪽에서 크게 돌며 이동
        AnimatedBuilder(
          animation: _a,
          builder: (_, __) {
            final align =
                _lerpCircle(_a.value, 0.55, const Alignment(-0.4, -0.7));
            return _GlowBlob(alignment: align, color: c1, radius: 0.75, alpha: 0.22);
          },
        ),
        // glow 2 — 아래쪽에서 작게 반대 방향
        AnimatedBuilder(
          animation: _b,
          builder: (_, __) {
            final align =
                _lerpCircle(-_b.value, 0.45, const Alignment(0.5, 0.6));
            return _GlowBlob(alignment: align, color: c2, radius: 0.6, alpha: 0.15);
          },
        ),
        widget.child,
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double radius; // 0 ~ 1 (화면 대비 지름 비율)
  final double alpha;

  const _GlowBlob({
    required this.alignment,
    required this.color,
    required this.radius,
    required this.alpha,
  });

  @override
  Widget build(BuildContext context) {
    // IgnorePointer + RepaintBoundary로 상호작용/리페인트 영향 최소화
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortest = constraints.biggest.shortestSide;
            final size = shortest * (radius * 2);
            return Align(
              alignment: alignment,
              child: SizedBox(
                width: size,
                height: size,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          color.withValues(alpha: alpha),
                          color.withValues(alpha: alpha * 0.5),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
