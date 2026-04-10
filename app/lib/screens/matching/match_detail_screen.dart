import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../providers/matching_provider.dart';
import '../../repositories/matching_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../widgets/common/user_avatar.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/game_repository.dart';
import '../../repositories/upload_repository.dart';
import 'opponent_profile_sheet.dart';

/// 노쇼 신고 확인 바텀시트
void _showNoshowConfirmDialog(
    BuildContext context, WidgetRef ref, String matchId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
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
            child: const Icon(Icons.report_outlined, color: Colors.red, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            '노쇼 신고',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '상대방: -30점 + 7일 매칭 제한\n나: +15점 보상\n\n허위 신고 시 제재를 받을 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9CA3AF),
              height: 1.6,
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
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(matchingRepositoryProvider)
                          .reportNoshow(matchId);
                      if (context.mounted) {
                        AppToast.success('노쇼 신고가 접수되었습니다.');
                        ref.invalidate(matchListProvider(null));
                        context.go('/matches');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.error('신고 실패: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('신고하기',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 경기 포기 확인 바텀시트
void _showForfeitConfirmDialog(
    BuildContext context, WidgetRef ref, String matchId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
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
            width: 36, height: 4,
            decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.flag_rounded, color: Colors.orange, size: 28),
          ),
          const SizedBox(height: 16),
          const Text('경기 포기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
            '포기하면 본인의 패배로 기록됩니다.\n점수가 하락할 수 있습니다. 정말 포기하시겠습니까?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), height: 1.6),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('취소', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref.read(matchingRepositoryProvider).forfeitMatch(matchId);
                      if (context.mounted) {
                        AppToast.info('경기를 포기했습니다. 패배로 기록됩니다.');
                        ref.invalidate(matchListProvider(null));
                        context.go('/matches');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.error('포기 처리 실패: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('포기하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 매칭 상세 화면
/// VS 레이아웃 + 매칭 정보 + 액션 버튼
class MatchDetailScreen extends ConsumerWidget {
  final String matchId;

  const MatchDetailScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchAsync = ref.watch(matchDetailProvider(matchId));

    return matchAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: FullScreenLoading(),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          title: const Text('매칭 상세'),
          backgroundColor: const Color(0xFF0A0A0A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/matches');
              }
            },
          ),
        ),
        body: ErrorView(
          message: '매칭 정보를 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(matchDetailProvider(matchId)),
        ),
      ),
      data: (match) {
        final shouldLock = false;
        // 노쇼 신고 가능 상태: CHAT 또는 CONFIRMED
        final shouldShowNoshow = match.isChat || match.isConfirmed;

        return PopScope(
          canPop: !shouldLock,
          child: Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            appBar: AppBar(
              title: const Text('매칭 상세'),
              backgroundColor: const Color(0xFF0A0A0A),
              elevation: 0,
              leading: shouldLock
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/matches');
                        }
                      },
                    ),
              actions: [
                if (shouldShowNoshow)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'noshow') {
                        _showNoshowConfirmDialog(context, ref, matchId);
                      } else if (value == 'forfeit') {
                        _showForfeitConfirmDialog(context, ref, matchId);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'forfeit',
                        child: Row(
                          children: [
                            Icon(Icons.flag_rounded, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text('경기 포기'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'noshow',
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('노쇼 신고'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: _MatchDetailContent(match: match, matchId: matchId),
          ),
        );
      },
    );
  }
}

class _MatchDetailContent extends ConsumerStatefulWidget {
  final Match match;
  final String matchId;

  const _MatchDetailContent({required this.match, required this.matchId});

  @override
  ConsumerState<_MatchDetailContent> createState() =>
      _MatchDetailContentState();
}

class _MatchDetailContentState extends ConsumerState<_MatchDetailContent> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    final match = widget.match;

    return SingleChildScrollView(
      child: Column(
        children: [
          // ─── VS 레이아웃 헤더 ───
          _VSHeader(match: match),

          // ─── 친선 게임 배너 ───
          if (match.isCasual)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.orange.shade50,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.handshake_outlined,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      '친선 게임 · 점수에 반영되지 않습니다',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── 상태 배지 ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _StatusBanner(status: match.status),
          ),

          // ─── 경기 정보 카드 ───
          _MatchInfoCard(match: match),

          const SizedBox(height: 20),

          // ─── 액션 버튼들 ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // 채팅하기
                if (match.isChat || match.isConfirmed) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          context.push('/chats/${match.chatRoomId}'),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                      label: const Text('채팅하기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 승부 결과 입력 버튼 (CHAT / CONFIRMED 상태에서 표시)
                if (match.isChat || match.isConfirmed) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: match.myResultSubmitted
                          ? null
                          : () => _showGameResultSheet(context, match),
                      icon: Icon(
                        match.myResultSubmitted
                            ? Icons.check_circle_rounded
                            : Icons.emoji_events_rounded,
                        size: 18,
                      ),
                      label: Text(match.myResultSubmitted
                          ? '결과 제출 완료 (상대 대기중)'
                          : '승부 결과 입력'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: match.myResultSubmitted
                            ? const Color(0xFF2A2A2A)
                            : AppTheme.secondaryColor,
                        foregroundColor: match.myResultSubmitted
                            ? AppTheme.textSecondary
                            : Colors.white,
                        disabledBackgroundColor: const Color(0xFF2A2A2A),
                        disabledForegroundColor: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],

                // 의의 제기 버튼 (COMPLETED 상태에서 표시)
                if (match.status == 'COMPLETED') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/disputes/create?matchId=${match.id}'),
                      icon: const Icon(Icons.gavel, size: 18),
                      label: const Text('의의 제기'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
                ],

                // 매칭 취소 버튼 (PENDING_ACCEPT 상태에서만 표시 — CHAT/CONFIRMED는 결과 입력 버튼으로 대체)
                if (match.isPendingAccept) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isCancelling
                          ? null
                          : () => _cancelMatch(context),
                      icon: _isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('매칭 취소'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 승부 결과 입력 바텀시트
  void _showGameResultSheet(BuildContext context, Match match) {
    String? selectedResult; // WIN | LOSS | DRAW
    int mannerScore = 3;
    bool isSubmitting = false;
    final List<File> photos = [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final canSubmit = selectedResult != null && photos.isNotEmpty && !isSubmitting;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 20),
                    const Text('승부 결과 입력', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('vs ${match.opponent.nickname}', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                    const SizedBox(height: 24),

                    // 승/무/패 버튼
                    Row(
                      children: [
                        _resultButton(ctx, '승리', 'WIN', Icons.emoji_events_rounded, Colors.blue, selectedResult, (v) => setSheetState(() => selectedResult = v)),
                        const SizedBox(width: 10),
                        _resultButton(ctx, '무승부', 'DRAW', Icons.handshake_rounded, const Color(0xFF6B7280), selectedResult, (v) => setSheetState(() => selectedResult = v)),
                        const SizedBox(width: 10),
                        _resultButton(ctx, '패배', 'LOSS', Icons.sentiment_dissatisfied_rounded, Colors.red, selectedResult, (v) => setSheetState(() => selectedResult = v)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 사진 촬영 (필수, 최대 2장)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('사진 첨부 (필수)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // 촬영한 사진들
                        ...photos.asMap().entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(entry.value, width: 72, height: 72, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: -4, right: -4,
                                  child: GestureDetector(
                                    onTap: () => setSheetState(() => photos.removeAt(entry.key)),
                                    child: Container(
                                      width: 22, height: 22,
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        // 추가 버튼 (2장 미만일 때)
                        if (photos.length < 2)
                          GestureDetector(
                            onTap: () async {
                              final picker = ImagePicker();
                              final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1200, maxHeight: 1200);
                              if (xFile != null) {
                                setSheetState(() => photos.add(File(xFile.path)));
                              }
                            },
                            child: Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF3A3A3A)),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.camera_alt_rounded, size: 24, color: AppTheme.textSecondary),
                                  const SizedBox(height: 2),
                                  Text('${photos.length}/2', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (photos.isEmpty) ...[
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('카메라로 결과 사진을 찍어주세요', style: TextStyle(fontSize: 11, color: AppTheme.textDisabled)),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // 매너 점수
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('매너 점수', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final score = i + 1;
                        return GestureDetector(
                          onTap: () => setSheetState(() => mannerScore = score),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              score <= mannerScore ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 32,
                              color: score <= mannerScore ? Colors.amber : const Color(0xFF2A2A2A),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 24),

                    // 제출 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: !canSubmit
                            ? null
                            : () async {
                                setSheetState(() => isSubmitting = true);
                                try {
                                  final uploadRepo = ref.read(uploadRepositoryProvider);

                                  // 사진 업로드
                                  final imageUrls = await uploadRepo.uploadGameProofs(
                                    photos.map((p) => p.path).toList(),
                                  );

                                  // matchId로 gameId 조회
                                  final matchDetail = await ref.read(matchingRepositoryProvider).getMatchDetail(match.id);
                                  final gameId = matchDetail.gameId;
                                  if (gameId == null) {
                                    AppToast.error('경기 정보를 찾을 수 없습니다.');
                                    return;
                                  }
                                  final gameRepo = ref.read(gameRepositoryProvider);
                                  final currentUser = ref.read(currentUserProvider);
                                  final game = await gameRepo.getGameDetail(gameId);
                                  final isRequester = game.requesterUserId == currentUser?.id;
                                  final myProfileId = isRequester ? game.requesterProfileId : game.opponentProfileId;
                                  final oppProfileId = isRequester ? game.opponentProfileId : game.requesterProfileId;
                                  String? winnerId;
                                  if (selectedResult == 'WIN') winnerId = myProfileId;
                                  if (selectedResult == 'LOSS') winnerId = oppProfileId;

                                  // 결과 제출
                                  await gameRepo.submitGameResult(
                                    gameId,
                                    myResult: selectedResult!,
                                    winnerId: winnerId,
                                    mannerScore: mannerScore,
                                  );

                                  // 증빙 사진 업로드
                                  if (imageUrls.isNotEmpty) {
                                    await gameRepo.uploadProofUrls(gameId, imageUrls);
                                  }

                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    AppToast.success('결과가 제출되었습니다.');
                                    ref.invalidate(matchDetailProvider(match.id));
                                    ref.invalidate(matchListProvider(null));
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setSheetState(() => isSubmitting = false);
                                    AppToast.error('결과 제출 실패: $e');
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF2A2A2A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: isSubmitting
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('결과 제출', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _resultButton(BuildContext context, String label, String value, IconData icon, Color color, String? selected, void Function(String) onTap) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: isSelected ? color : AppTheme.textSecondary),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isSelected ? color : AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  void _showOpponentProfile(BuildContext context, MatchOpponent opponent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => OpponentProfileSheet(opponent: opponent),
    );
  }

  void _showConfirmMatchDialog(BuildContext context) {
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    final venueController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.fromLTRB(
                  24, 20, 24, MediaQuery.of(sheetContext).padding.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Icon
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.sports_score_outlined,
                          color: AppTheme.primaryColor, size: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      '경기 확정',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 경기 날짜
                  const Text(
                    '경기 날짜',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: sheetContext,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setSheetState(() => selectedDate = date);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        selectedDate != null
                            ? '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}'
                            : '날짜를 선택해주세요',
                        style: TextStyle(
                          color: selectedDate != null
                              ? AppTheme.textPrimary
                              : AppTheme.textDisabled,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 경기 시간
                  const Text(
                    '경기 시간',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final time = await showTimePicker(
                        context: sheetContext,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        setSheetState(() => selectedTime = time);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        selectedTime != null
                            ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                            : '시간을 선택해주세요',
                        style: TextStyle(
                          color: selectedTime != null
                              ? AppTheme.textPrimary
                              : AppTheme.textDisabled,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 장소
                  const Text(
                    '장소',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: venueController,
                    decoration: InputDecoration(
                      hintText: '장소명을 입력해주세요',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // 버튼 영역
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            side:
                                const BorderSide(color: Color(0xFF2A2A2A)),
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
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (selectedDate == null ||
                                      selectedTime == null ||
                                      venueController.text.trim().isEmpty) {
                                    AppToast.warning('날짜, 시간, 장소를 모두 입력해주세요.');
                                    return;
                                  }

                                  setSheetState(() => isSubmitting = true);

                                  try {
                                    final repo =
                                        ref.read(matchingRepositoryProvider);
                                    final dateStr =
                                        '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';
                                    final timeStr =
                                        '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}';

                                    await repo.confirmMatch(
                                      widget.matchId,
                                      scheduledDate: dateStr,
                                      scheduledTime: timeStr,
                                      venueName: venueController.text.trim(),
                                    );

                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }

                                    if (mounted) {
                                      AppToast.success('경기가 확정되었습니다.');
                                      ref.invalidate(matchDetailProvider(
                                          widget.matchId));
                                      ref.invalidate(matchListProvider(null));
                                    }
                                  } catch (e) {
                                    setSheetState(
                                        () => isSubmitting = false);
                                    if (mounted) {
                                      AppToast.error('경기 확정 실패: ${e.toString()}');
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('확정하기',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => venueController.dispose());
  }

  Future<void> _cancelMatch(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
                color: AppTheme.errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cancel_outlined,
                  color: AppTheme.errorColor, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              '매칭 취소',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '이 매칭을 취소하시겠습니까?\n취소 후에는 되돌릴 수 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF2A2A2A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('아니오',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('취소하기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      await repo.cancelMatch(widget.matchId, reason: '사용자 취소');

      if (mounted) {
        AppToast.success('매칭이 취소되었습니다.');
        ref.invalidate(matchListProvider(null));
        // 매칭 목록으로 이동하고 목록 갱신
        context.go('/matches');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('취소 실패: ${e.toString()}');
      }
      if (mounted) setState(() => _isCancelling = false);
    }
  }
}

/// VS 레이아웃 헤더
class _VSHeader extends StatelessWidget {
  final Match match;

  const _VSHeader({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryColor, AppTheme.primaryDark],
        ),
      ),
      child: Row(
        children: [
          // 내 프로필 (좌측)
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '나',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // VS 텍스트
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),

          // 상대 프로필 (우측)
          Expanded(
            child: Column(
              children: [
                UserAvatar(
                  imageUrl: match.opponent.profileImageUrl,
                  size: 64,
                  nickname: match.opponent.nickname,
                ),
                const SizedBox(height: 8),
                Text(
                  match.opponent.nickname,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 상태 배너
class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'PENDING_ACCEPT':
        color = Colors.orange;
        label = '수락 대기 중';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'CHAT':
        return const SizedBox.shrink();
      case 'CONFIRMED':
        color = AppTheme.secondaryColor;
        label = '경기 확정됨';
        icon = Icons.check_circle_rounded;
        break;
      case 'COMPLETED':
        color = const Color(0xFF9CA3AF);
        label = '경기 완료';
        icon = Icons.sports_score_rounded;
        break;
      default:
        color = AppTheme.textDisabled;
        label = status;
        icon = Icons.info_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// 매칭 정보 카드
class _MatchInfoCard extends StatelessWidget {
  final Match match;

  const _MatchInfoCard({required this.match});

  String _formatMatchDateTime(String? dateRaw, String? timeSlot) {
    String datePart = '';
    if (dateRaw != null) {
      try {
        final d = dateRaw.length >= 10 ? dateRaw.substring(0, 10) : dateRaw;
        final parts = d.split('-');
        if (parts.length == 3) {
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          final date = DateTime(int.parse(parts[0]), month, day);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final diff = date.difference(today).inDays;
          final dayLabel = diff == 0 ? ' (오늘)' : diff == 1 ? ' (내일)' : '';
          datePart = '${month}월 ${day}일$dayLabel';
        }
      } catch (_) {
        datePart = dateRaw;
      }
    }
    String timePart = '';
    if (timeSlot != null && timeSlot != 'ANY') {
      timePart = match.desiredTimeSlotDisplayName;
    } else if (timeSlot == 'ANY') {
      timePart = '하루종일';
    }
    if (datePart.isNotEmpty && timePart.isNotEmpty) return '$datePart · $timePart';
    if (datePart.isNotEmpty) return datePart;
    return timePart;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.sports_score_rounded,
            label: '종목',
            value: match.sportTypeDisplayName,
          ),
          if (match.pinName != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: '핀',
              value: match.pinName!,
            ),
          ],
          if (match.desiredDate != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              label: '경기 일시',
              value: _formatMatchDateTime(match.desiredDate, match.desiredTimeSlot),
            ),
          ],
          if (match.scheduledDate != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.event_available_rounded,
              label: '확정 날짜',
              value: match.scheduledDate!,
            ),
          ],
          if (match.scheduledTime != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.schedule_rounded,
              label: '확정 시간',
              value: match.scheduledTime!,
            ),
          ],
          if (match.venueName != null) ...[
            const Divider(height: 20),
            _InfoRow(
              icon: Icons.place_rounded,
              label: '장소',
              value: match.venueName!,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppTheme.primaryColor),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
