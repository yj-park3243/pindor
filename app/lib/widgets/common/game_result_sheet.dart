import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../core/utils/permission_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/matching_provider.dart';
import '../../repositories/game_repository.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/upload_repository.dart';
import 'app_toast.dart';

/// 승부 결과 입력 바텀시트
///
/// [matchId] 매칭 ID (필수)
/// [opponentNickname] 상대 닉네임 (있으면 "vs 닉네임" 표시)
/// [onSubmitted] 제출 완료 콜백
void showGameResultSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String matchId,
  String? opponentNickname,
  String? initialVerificationCode,
  VoidCallback? onSubmitted,
}) {
  String? selectedResult;
  int mannerScore = 3;
  bool isSubmitting = false;
  final List<File> photos = [];
  final verificationCodeController = TextEditingController(
    text: initialVerificationCode ?? '',
  );

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final canSubmit = !isSubmitting;

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
                  // 핸들
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '승부 결과',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  if (opponentNickname != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'vs $opponentNickname',
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // 승/무/패 버튼
                  Row(
                    children: [
                      _resultOptionButton('승리', 'WIN',
                          Symbols.emoji_events_rounded, Colors.blue,
                          selected: selectedResult,
                          onTap: (v) =>
                              setSheetState(() => selectedResult = v)),
                      const SizedBox(width: 10),
                      _resultOptionButton('무승부', 'DRAW',
                          Symbols.handshake_rounded, const Color(0xFF6B7280),
                          selected: selectedResult,
                          onTap: (v) =>
                              setSheetState(() => selectedResult = v)),
                      const SizedBox(width: 10),
                      _resultOptionButton(
                          '패배',
                          'LOSS',
                          Symbols.sentiment_dissatisfied_rounded,
                          Colors.red,
                          selected: selectedResult,
                          onTap: (v) =>
                              setSheetState(() => selectedResult = v)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 인증번호 입력
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('상대방 인증번호 입력',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '상대방에게 인증번호를 확인하고 입력해주세요',
                      style: TextStyle(fontSize: 11, color: AppTheme.textDisabled),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: verificationCodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 12,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '● ● ● ●',
                      hintStyle: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.15),
                        letterSpacing: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 사진 첨부 (선택)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('사진 첨부 (선택)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...photos.asMap().entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(entry.value,
                                    width: 72, height: 72, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () => setSheetState(
                                      () => photos.removeAt(entry.key)),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (photos.length < 2)
                        GestureDetector(
                          onTap: () async {
                            final source =
                                await showModalBottomSheet<ImageSource>(
                              context: ctx,
                              backgroundColor: const Color(0xFF1E1E1E),
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16))),
                              builder: (innerCtx) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                        Symbols.photo_camera_rounded,
                                        color: Colors.white),
                                    title: const Text('카메라',
                                        style:
                                            TextStyle(color: Colors.white)),
                                    onTap: () => Navigator.pop(
                                        innerCtx, ImageSource.camera),
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                        Symbols.photo_library_rounded,
                                        color: Colors.white),
                                    title: const Text('갤러리',
                                        style:
                                            TextStyle(color: Colors.white)),
                                    onTap: () => Navigator.pop(
                                        innerCtx, ImageSource.gallery),
                                  ),
                                ],
                              ),
                            );
                            if (source == null) return;

                            // 카메라만 권한 체크 (갤러리는 PHPicker로 권한 불필요)
                            if (source == ImageSource.camera) {
                              final granted = await PermissionHelper.requestCamera(ctx);
                              if (!granted) return;
                            }

                            final picker = ImagePicker();
                            final xFile = await picker.pickImage(
                                source: source,
                                imageQuality: 80,
                                maxWidth: 1200,
                                maxHeight: 1200);
                            if (xFile != null) {
                              setSheetState(() => photos.add(File(xFile.path)));
                            }
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFF3A3A3A)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Symbols.add_a_photo_rounded,
                                    size: 24, color: AppTheme.textSecondary),
                                const SizedBox(height: 2),
                                Text('${photos.length}/2',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary)),
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
                      child: Text(
                          '인증 사진을 첨부해주세요 (ex. 당구대, 코트, 경기장 등)',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textDisabled)),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 매너 점수
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('매너 점수',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final score = i + 1;
                      return GestureDetector(
                        onTap: () =>
                            setSheetState(() => mannerScore = score),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            score <= mannerScore
                                ? Symbols.star_rounded
                                : Symbols.star_outline_rounded,
                            size: 32,
                            color: score <= mannerScore
                                ? Colors.amber
                                : const Color(0xFF2A2A2A),
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
                              if (selectedResult == null) {
                                AppToast.warning('승부 결과를 선택해주세요.');
                                return;
                              }
                              final code = verificationCodeController.text.trim();
                              if (code.length != 4) {
                                AppToast.warning('상대방의 4자리 인증번호를 입력해주세요.');
                                return;
                              }
                              setSheetState(() => isSubmitting = true);
                              try {
                                List<String> imageUrls = [];
                                if (photos.isNotEmpty) {
                                  final uploadRepo =
                                      ref.read(uploadRepositoryProvider);
                                  imageUrls =
                                      await uploadRepo.uploadGameProofs(
                                    photos.map((p) => p.path).toList(),
                                  );
                                }

                                final matchDetail = await ref
                                    .read(matchingRepositoryProvider)
                                    .getMatchDetail(matchId);
                                final gameId = matchDetail.gameId;
                                if (gameId == null) {
                                  AppToast.error('경기 정보를 찾을 수 없습니다.');
                                  setSheetState(
                                      () => isSubmitting = false);
                                  return;
                                }
                                final gameRepo =
                                    ref.read(gameRepositoryProvider);
                                final currentUser =
                                    ref.read(currentUserProvider);
                                final game =
                                    await gameRepo.getGameDetail(gameId);
                                final isRequester =
                                    game.requesterUserId ==
                                        currentUser?.id;
                                final myProfileId = isRequester
                                    ? game.requesterProfileId
                                    : game.opponentProfileId;
                                final oppProfileId = isRequester
                                    ? game.opponentProfileId
                                    : game.requesterProfileId;
                                String? winnerId;
                                if (selectedResult == 'WIN') {
                                  winnerId = myProfileId;
                                }
                                if (selectedResult == 'LOSS') {
                                  winnerId = oppProfileId;
                                }

                                await gameRepo.submitGameResult(
                                  gameId,
                                  myResult: selectedResult!,
                                  winnerId: winnerId,
                                  mannerScore: mannerScore,
                                  verificationCode: code,
                                );

                                if (imageUrls.isNotEmpty) {
                                  await gameRepo.uploadProofUrls(
                                      gameId, imageUrls);
                                }

                                if (ctx.mounted) Navigator.pop(ctx);
                                AppToast.success('결과가 제출되었습니다.');
                                ref.invalidate(
                                    matchDetailProvider(matchId));
                                ref.invalidate(matchListProvider(null));
                                onSubmitted?.call();
                              } catch (e) {
                                if (ctx.mounted) {
                                  setSheetState(
                                      () => isSubmitting = false);
                                  AppToast.error('결과 제출 실패: $e');
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF2A2A2A),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : const Text('결과 제출',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
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

Widget _resultOptionButton(
  String label,
  String value,
  IconData icon,
  Color color, {
  required String? selected,
  required void Function(String) onTap,
}) {
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
          border: Border.all(
              color: isSelected ? color : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 28,
                color: isSelected ? color : AppTheme.textSecondary),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? color : AppTheme.textSecondary)),
          ],
        ),
      ),
    ),
  );
}
