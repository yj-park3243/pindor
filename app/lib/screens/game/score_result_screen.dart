import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../widgets/common/score_display.dart';

/// 점수 변동 결과 화면 (PRD SCREEN-029)
/// 애니메이션: 이전점수 → 새점수, 랭킹 변동 표시, 공유 버튼
class ScoreResultScreen extends StatefulWidget {
  final String gameId;
  final int previousScore;
  final int newScore;
  final int scoreDelta;
  final bool isWin;
  final int? previousRank;
  final int? newRank;
  final bool isCasual;
  final bool isPlacement;               // 배치 게임 진행 중 여부
  final int? placementGamesRemaining;   // 배치 완료 후 남은 횟수

  const ScoreResultScreen({
    super.key,
    required this.gameId,
    required this.previousScore,
    required this.newScore,
    required this.scoreDelta,
    required this.isWin,
    this.previousRank,
    this.newRank,
    this.isCasual = false,
    this.isPlacement = false,
    this.placementGamesRemaining,
  });

  @override
  State<ScoreResultScreen> createState() => _ScoreResultScreenState();
}

class _ScoreResultScreenState extends State<ScoreResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _titleController;
  late AnimationController _scoreController;
  late AnimationController _rankController;
  late AnimationController _confettiController;
  late Animation<double> _titleFade;
  late Animation<double> _titleScale;
  late Animation<double> _rankFade;


  @override
  void initState() {
    super.initState();

    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _rankController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _titleFade = CurvedAnimation(
        parent: _titleController, curve: Curves.easeOut);
    _titleScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _titleController, curve: Curves.easeOutBack),
    );
    _rankFade = CurvedAnimation(
        parent: _rankController, curve: Curves.easeOut);

    // 순차 애니메이션
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _titleController.forward();
        if (widget.isWin) {
          HapticFeedback.heavyImpact();
          _confettiController.forward();
        }
      }
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _scoreController.forward();
    });
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) _rankController.forward();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _scoreController.dispose();
    _rankController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // ─── 결과 타이틀 ───
              FadeTransition(
                opacity: _titleFade,
                child: ScaleTransition(
                  scale: _titleScale,
                  child: Column(
                    children: [
                      // 결과 아이콘
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: (widget.isWin
                                  ? AppTheme.secondaryColor
                                  : AppTheme.errorColor)
                              .withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isWin
                              ? Icons.emoji_events_rounded
                              : Icons.sentiment_dissatisfied_rounded,
                          size: 44,
                          color: widget.isWin
                              ? AppTheme.secondaryColor
                              : AppTheme.errorColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.isWin ? '승리!' : '패배',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: widget.isWin
                              ? AppTheme.secondaryColor
                              : AppTheme.errorColor,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (widget.isCasual)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: Colors.orange.shade300),
                          ),
                          child: Text(
                            '친선 게임 · 점수 미반영',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        )
                      else
                        const Text(
                          '경기가 완료되었습니다',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ─── 점수 변동 (친선: 안내 문구 / 배치 중: 배치 안내 / 랭크: 애니메이션) ───
              if (widget.isCasual)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.handshake_outlined,
                          size: 36, color: Colors.orange.shade600),
                      const SizedBox(height: 10),
                      Text(
                        '이 게임은 점수에 반영되지 않습니다',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '친선 게임 결과는 친선 전적에만 기록됩니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else if (widget.isPlacement)
                _PlacementProgressCard(
                  placementGamesRemaining: widget.placementGamesRemaining,
                )
              else
                AnimatedScoreCounter(
                  fromScore: widget.previousScore,
                  toScore: widget.newScore,
                  duration: const Duration(milliseconds: 1500),
                ),

              const SizedBox(height: 24),

              // ─── 랭킹 변동 (랭크 게임에서만) ───
              if (!widget.isCasual &&
                  widget.previousRank != null &&
                  widget.newRank != null)
                FadeTransition(
                  opacity: _rankFade,
                  child: _RankChangeCard(
                    previousRank: widget.previousRank!,
                    newRank: widget.newRank!,
                  ),
                ),

              const Spacer(flex: 2),

              // ─── 버튼 영역 ───
              Column(
                children: [
                  // 공유 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: 결과 공유 기능
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('공유 기능 준비 중입니다.')),
                        );
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('결과 공유하기'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 홈/랭킹 버튼
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () => context.go(AppRoutes.home),
                            child: const Text('홈으로'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () => context.go(AppRoutes.map),
                            child: const Text('랭킹 보기'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}


/// 배치 게임 진행 상황 카드 (점수 결과 화면에서 배치 중일 때 표시)
class _PlacementProgressCard extends StatelessWidget {
  final int? placementGamesRemaining;

  const _PlacementProgressCard({this.placementGamesRemaining});

  @override
  Widget build(BuildContext context) {
    final played = 5 - (placementGamesRemaining ?? 5);
    final remaining = placementGamesRemaining ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.hourglass_top_rounded,
              size: 36, color: Colors.orange.shade600),
          const SizedBox(height: 10),
          Text(
            '배치 게임 진행 중',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$played / 5 완료',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.orange.shade600,
            ),
          ),
          const SizedBox(height: 8),
          // 진행 바
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: played / 5,
              minHeight: 8,
              backgroundColor: Colors.orange.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade500),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remaining > 0
                ? '${remaining}경기 후 점수가 공개됩니다'
                : '배치가 완료되었습니다! 점수가 곧 공개됩니다',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RankChangeCard extends StatelessWidget {
  final int previousRank;
  final int newRank;

  const _RankChangeCard(
      {required this.previousRank, required this.newRank});

  @override
  Widget build(BuildContext context) {
    final improved = newRank < previousRank;
    final rankDiff = (previousRank - newRank).abs();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.leaderboard_rounded,
              size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$previousRank위',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded,
                size: 16, color: AppTheme.textSecondary),
          ),
          Text(
            '$newRank위',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          if (rankDiff != 0)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (improved
                        ? AppTheme.secondaryColor
                        : AppTheme.errorColor)
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    improved
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: improved
                        ? AppTheme.secondaryColor
                        : AppTheme.errorColor,
                  ),
                  Text(
                    '$rankDiff',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: improved
                          ? AppTheme.secondaryColor
                          : AppTheme.errorColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
