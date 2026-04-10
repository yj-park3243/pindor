import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../models/game.dart';
import '../../providers/game_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';

/// 결과 인증 대기/확인 화면 (PRD SCREEN-027/028)
class GameConfirmScreen extends ConsumerWidget {
  final String gameId;

  const GameConfirmScreen({super.key, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameAsync = ref.watch(gameResultProvider(gameId));

    return Scaffold(
      appBar: AppBar(title: const Text('결과 인증')),
      body: gameAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(message: '경기 정보를 불러올 수 없습니다.'),
        data: (game) => _GameConfirmContent(game: game, gameId: gameId),
      ),
    );
  }
}

class _GameConfirmContent extends ConsumerStatefulWidget {
  final Game game;
  final String gameId;

  const _GameConfirmContent({required this.game, required this.gameId});

  @override
  ConsumerState<_GameConfirmContent> createState() =>
      _GameConfirmContentState();
}

class _GameConfirmContentState extends ConsumerState<_GameConfirmContent> {
  bool _isLoading = false;

  Future<void> _confirmResult(bool isConfirmed, {String? reason}) async {
    setState(() => _isLoading = true);
    try {
      final notifier = ref.read(gameResultProvider(widget.gameId).notifier);
      final result = await notifier.confirmResult(
          isConfirmed: isConfirmed, comment: reason);

      // 이의 신청인 경우 submitDispute 호출
      if (!isConfirmed && reason != null && reason.isNotEmpty) {
        await notifier.submitDispute(reason: reason);
      }

      if (mounted && isConfirmed && result != null) {
        context.go(
          '/games/${widget.gameId}/score-result',
          extra: {
            'previousScore': result.previousScore,
            'newScore': result.newScore,
            'scoreDelta': result.scoreDelta,
            'isWin': result.isWin,
            'previousRank': result.previousRank,
            'newRank': result.newRank,
          },
        );
      } else if (mounted) {
        AppToast.info('이의가 제기되었습니다.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('오류: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final myResult = game.myResult;
    final opponentResult = game.opponentResult;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상태 안내
          _StatusBanner(resultStatus: game.resultStatus),
          const SizedBox(height: 24),

          // 내가 제출한 결과
          if (myResult != null) ...[
            const Text(
              '내 결과',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            _ResultCard(
              myScore: myResult.myScore,
              opponentScore: myResult.opponentScore,
              isMyResult: true,
            ),
          ],

          const SizedBox(height: 16),

          // 상대가 제출한 결과
          if (opponentResult != null) ...[
            const Text(
              '상대 결과',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            _ResultCard(
              myScore: opponentResult.opponentScore,
              opponentScore: opponentResult.myScore,
              isMyResult: false,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_empty, color: AppTheme.textSecondary),
                  SizedBox(width: 10),
                  Text(
                    '상대방 결과 입력 대기 중...',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],

          // 증빙 사진
          if (game.proofs.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              '증빙 사진',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: game.proofs.map((proof) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    proof.imageUrl,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                );
              }).toList(),
            ),
          ],

          // 인증 버튼 (상대 결과가 있고 아직 인증 안 된 경우)
          if (opponentResult != null &&
              !opponentResult.isConfirmed &&
              game.resultStatus == 'PROOF_UPLOADED') ...[
            const SizedBox(height: 32),
            const Text(
              '상대방이 입력한 결과가 맞나요?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _showDisputeDialog(),
                    icon: const Icon(Icons.thumb_down_outlined),
                    label: const Text('이의 신청'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                      side: const BorderSide(color: AppTheme.errorColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _confirmResult(true),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.thumb_up),
                    label: const Text('인증'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showDisputeDialog() {
    final reasonController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gavel_outlined,
                    color: Colors.red, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                '이의 신청',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '이의 신청 사유를 입력해주세요.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: '잘못된 부분을 설명해주세요...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF2A2A2A)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('취소',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9CA3AF))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final reason = reasonController.text.trim();
                        Navigator.pop(ctx);
                        _confirmResult(false,
                            reason: reason.isNotEmpty ? reason : null);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('이의 제기',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) => reasonController.dispose());
  }
}

class _StatusBanner extends StatelessWidget {
  final String resultStatus;

  const _StatusBanner({required this.resultStatus});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    String description;
    IconData icon;

    switch (resultStatus) {
      case 'PROOF_UPLOADED':
        color = AppTheme.warningColor;
        label = '인증 대기';
        description = '상대방의 확인을 기다리고 있습니다.';
        icon = Icons.hourglass_top;
        break;
      case 'VERIFIED':
        color = AppTheme.secondaryColor;
        label = '인증 완료';
        description = '결과가 확인되어 점수가 반영되었습니다.';
        icon = Icons.check_circle;
        break;
      case 'DISPUTED':
        color = AppTheme.errorColor;
        label = '이의 신청';
        description = '이의가 제기되어 관리자 검토 중입니다.';
        icon = Icons.report;
        break;
      default:
        color = AppTheme.textSecondary;
        label = '입력 대기';
        description = '경기 결과를 입력해주세요.';
        icon = Icons.assignment;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withOpacity(0.8),
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

class _ResultCard extends StatelessWidget {
  final int myScore;
  final int opponentScore;
  final bool isMyResult;

  const _ResultCard({
    required this.myScore,
    required this.opponentScore,
    required this.isMyResult,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              Text(
                isMyResult ? '나' : '상대',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$myScore',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Text(
            'VS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          Column(
            children: [
              Text(
                isMyResult ? '상대' : '나',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$opponentScore',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
