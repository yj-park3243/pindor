import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../providers/matching_provider.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:bottom_picker/bottom_picker.dart';
import 'package:bottom_picker/resources/time.dart';

import '../../widgets/common/user_avatar.dart';
import '../../widgets/common/game_result_sheet.dart';
import '../../widgets/common/score_display.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../core/network/socket_service.dart';
import '../../widgets/report/report_bottom_sheet.dart';
import 'opponent_profile_sheet.dart';
import '../../repositories/block_repository.dart';

/// 노쇼 신고 확인 바텀시트 (사진 필수)
void _showNoshowConfirmDialog(
    BuildContext context, WidgetRef ref, String matchId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _NoshowReportSheet(matchId: matchId),
  );
}

/// 노쇼 신고 바텀시트 (사진 필수 첨부)
class _NoshowReportSheet extends ConsumerStatefulWidget {
  final String matchId;
  const _NoshowReportSheet({required this.matchId});

  @override
  ConsumerState<_NoshowReportSheet> createState() => _NoshowReportSheetState();
}

class _NoshowReportSheetState extends ConsumerState<_NoshowReportSheet> {
  final List<File> _images = [];
  bool _isSubmitting = false;
  static const _maxImages = 3;

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= _maxImages) {
      AppToast.warning('사진은 최대 ${_maxImages}장까지 첨부 가능합니다.');
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked != null) {
      setState(() => _images.add(File(picked.path)));
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _showImageSourcePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
            child: const Text('카메라로 촬영'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
            child: const Text('갤러리에서 선택'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          isDestructiveAction: true,
          child: const Text('취소'),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_images.isEmpty) {
      AppToast.warning('증거 사진을 1장 이상 첨부해주세요.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      // 1) 사진 업로드
      final imageUrls = await ref
          .read(uploadRepositoryProvider)
          .uploadGameProofs(_images.map((f) => f.path).toList());
      // 2) 노쇼 신고 (이미지 URL 포함)
      await ref
          .read(matchingRepositoryProvider)
          .reportNoshow(widget.matchId, imageUrls: imageUrls);
      if (mounted) {
        Navigator.pop(context);
        AppToast.success('노쇼 신고가 접수되었습니다.');
        ref.invalidate(matchListProvider(null));
        context.go('/matches');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '신고에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.report_outlined, color: Colors.red, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            '노쇼 신고',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            '상대방: -30점 + 7일 매칭 제한\n나: +15점 보상\n\n허위 신고 시 제재를 받을 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), height: 1.6),
          ),
          const SizedBox(height: 20),

          // 사진 첨부 영역
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '증거 사진 (필수, 최대 ${_maxImages}장)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // 추가 버튼
                if (_images.length < _maxImages)
                  GestureDetector(
                    onTap: _showImageSourcePicker,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3A3A3A)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.camera_alt_outlined, color: Color(0xFF9CA3AF), size: 24),
                          const SizedBox(height: 4),
                          Text(
                            '${_images.length}/$_maxImages',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 첨부된 이미지 미리보기
                ..._images.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            entry.value,
                            width: 80, height: 80, fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4, right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(entry.key),
                            child: Container(
                              width: 22, height: 22,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 버튼
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF2A2A2A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('취소',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _images.isEmpty ? const Color(0xFF3A3A3A) : Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('신고하기',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 유저 차단 확인 바텀시트
void _showBlockConfirmDialog(
    BuildContext context, WidgetRef ref, String opponentId, String opponentNickname) {
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
            child: const Icon(Icons.block, color: Colors.red, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            '유저 차단',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '차단하면 해당 유저와 더 이상 매칭되지 않습니다.\n차단하시겠습니까?',
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
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref.read(blockRepositoryProvider).blockUser(opponentId);
                      if (context.mounted) {
                        AppToast.success('차단되었습니다.');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.error(extractErrorMessage(e, '차단에 실패했습니다.'));
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
                  child: const Text(
                    '차단하기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
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
                        AppToast.error(extractErrorMessage(e, '포기 처리에 실패했습니다.'));
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

/// 매칭 상태에 따라 적절한 탭으로 뒤로가기
void _navigateBackFromDetail(BuildContext context, String? status) {
  if (context.canPop()) {
    context.pop();
  } else if (status == 'COMPLETED') {
    context.go('/matches', extra: {'initialTab': 1});
  } else if (status == 'CANCELLED') {
    context.go('/matches', extra: {'initialTab': 2});
  } else {
    context.go('/matches');
  }
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
                      onPressed: () => _navigateBackFromDetail(context, match.status),
                    ),
              actions: [
                PullDownButton(
                  itemBuilder: (ctx) => [
                    if (shouldShowNoshow) ...[
                      PullDownMenuItem(
                        title: '경기 포기',
                        icon: Icons.flag_rounded,
                        iconColor: Colors.orange,
                        onTap: () => _showForfeitConfirmDialog(context, ref, matchId),
                      ),
                      const PullDownMenuDivider(),
                      PullDownMenuItem(
                        title: '노쇼 신고',
                        icon: Icons.warning_amber,
                        isDestructive: true,
                        onTap: () => _showNoshowConfirmDialog(context, ref, matchId),
                      ),
                      const PullDownMenuDivider(),
                    ],
                    PullDownMenuItem(
                      title: '차단',
                      icon: Icons.block,
                      isDestructive: true,
                      onTap: () => _showBlockConfirmDialog(
                        context,
                        ref,
                        match.opponent.id,
                        match.opponent.nickname,
                      ),
                    ),
                    const PullDownMenuDivider(),
                    PullDownMenuItem(
                      title: '신고',
                      icon: Icons.flag_outlined,
                      isDestructive: true,
                      onTap: () => showReportBottomSheet(
                        context,
                        targetType: 'MATCH',
                        targetId: matchId,
                      ),
                    ),
                  ],
                  buttonBuilder: (ctx, showMenu) => IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: showMenu,
                  ),
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
  bool _resultSubmitted = false;
  String? _lastKnownStatus;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 매칭 룸 조인 (실시간 상태 변경 수신)
    SocketService.instance.joinMatch(widget.matchId);

    // 소켓 매칭 상태 변경 이벤트 구독
    _statusSub = SocketService.instance.onMatchStatusChanged
        .where((data) => data['matchId'] == widget.matchId)
        .listen((data) {
      final status = data['status'] as String?;
      ref.invalidate(matchDetailProvider(widget.matchId));

      if (status == 'COMPLETED' && mounted) {
        _lastKnownStatus = 'COMPLETED';
      } else if (status == 'CANCELLED' && mounted) {
        _lastKnownStatus = 'CANCELLED';
        AppToast.info('상대방이 매칭을 취소했습니다.');
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    // 활성 매칭은 룸 유지 (main_tab_screen이 COMPLETED/CANCELLED 시 퇴장 처리)
    // COMPLETED/CANCELLED일 때만 퇴장
    final status = _lastKnownStatus ?? widget.match.status;
    if (status == 'COMPLETED' || status == 'CANCELLED') {
      SocketService.instance.leaveMatch(widget.matchId);
    }
    super.dispose();
  }

  void _goBack(BuildContext context) {
    final status = _lastKnownStatus ?? widget.match.status;
    ref.invalidate(matchListProvider(null));
    _navigateBackFromDetail(context, status);
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final isResultSubmitted = match.myResultSubmitted || _resultSubmitted;

    return Column(
        children: [
          const SizedBox(height: 8),

          // ─── 매칭 카드 ───
          _MatchupCard(match: match),

          const SizedBox(height: 16),

          // ─── 액션 버튼들 ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // 채팅하기
                if (match.isChat || match.isConfirmed) ...[
                  Builder(builder: (context) {
                    final chatUnread = ref.watch(roomUnreadCountProvider(match.chatRoomId));
                    return SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: Badge(
                        isLabelVisible: chatUnread > 0,
                        label: Text(
                          chatUnread > 99 ? '99+' : '$chatUnread',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        backgroundColor: Colors.red,
                        largeSize: 22,
                        offset: const Offset(-4, -8),
                        child: SizedBox(
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
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                ],

                // 승부 결과 버튼 (CHAT / CONFIRMED 상태에서 표시)
                if (match.isChat || match.isConfirmed) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: isResultSubmitted
                          ? null
                          : () async {
                              // 채팅방 존재 여부 체크
                              if (match.chatRoomId.isEmpty) {
                                AppToast.info('채팅방이 아직 생성되지 않았습니다. 상대방과 먼저 채팅을 시작해주세요.');
                                return;
                              }
                              if (!context.mounted) return;
                              // 수신된 인증번호가 있으면 자동 입력
                              final receivedCode = match.chatRoomId.isNotEmpty
                                  ? ref.read(receivedVerificationCodeProvider(match.chatRoomId))
                                  : null;
                              showGameResultSheet(
                                context,
                                ref: ref,
                                matchId: match.id,
                                opponentNickname: match.opponent.nickname,
                                initialVerificationCode: receivedCode,
                                onSubmitted: () {
                                  setState(() => _resultSubmitted = true);
                                },
                              );
                            },
                      icon: Icon(
                        isResultSubmitted
                            ? Icons.check_circle_rounded
                            : Icons.emoji_events_rounded,
                        size: 18,
                      ),
                      label: Text(isResultSubmitted
                          ? '결과 제출 완료 (상대 대기중)'
                          : '승부 결과'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isResultSubmitted
                            ? const Color(0xFF2A2A2A)
                            : AppTheme.secondaryColor,
                        foregroundColor: isResultSubmitted
                            ? AppTheme.textSecondary
                            : Colors.white,
                        disabledBackgroundColor: const Color(0xFF2A2A2A),
                        disabledForegroundColor: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],

                // 매칭 취소 버튼 (PENDING_ACCEPT 상태에서만 표시)
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

                // 의의 제기 버튼 (COMPLETED 상태에서 맨 하단)
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
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
        ],
    );
  }


  void _showOpponentProfile(BuildContext context, MatchOpponent opponent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OpponentProfileSheet(opponent: opponent),
    );
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
        AppToast.error(extractErrorMessage(e, '매칭 취소에 실패했습니다.'));
      }
      if (mounted) setState(() => _isCancelling = false);
    }
  }
}

/// 매칭 카드 (VS 레이아웃 + 경기 정보 통합)
class _MatchupCard extends ConsumerWidget {
  final Match match;

  const _MatchupCard({required this.match});

  IconData _sportIcon(String sportType) {
    switch (sportType) {
      case 'GOLF':
        return Icons.golf_course_rounded;
      case 'TENNIS':
        return Icons.sports_tennis_rounded;
      case 'TABLE_TENNIS':
        return Icons.sports_tennis_rounded;
      case 'BILLIARDS':
        return Icons.circle_outlined;
      default:
        return Icons.sports_rounded;
    }
  }

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
    if (datePart.isNotEmpty && timePart.isNotEmpty) {
      return '$datePart · $timePart';
    }
    if (datePart.isNotEmpty) return datePart;
    return timePart;
  }

  Widget _buildResultTag(String? gameResult, bool isMe) {
    if (!match.isCompleted || gameResult == null) {
      return const SizedBox.shrink();
    }

    String label;
    Color color;

    if (gameResult == 'DRAW') {
      label = '무승부';
      color = const Color(0xFF9CA3AF);
    } else if ((gameResult == 'WIN' && isMe) || (gameResult == 'LOSS' && !isMe)) {
      label = '승리';
      color = AppTheme.secondaryColor;
    } else {
      label = '패배';
      color = AppTheme.errorColor;
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, String label) {
    Color color;
    IconData icon;
    switch (status) {
      case 'PENDING_ACCEPT':
        color = Colors.orange;
        icon = Icons.hourglass_top_rounded;
        break;
      case 'CHAT':
      case 'CONFIRMED':
        color = Colors.blue;
        icon = Icons.chat_bubble_rounded;
        break;
      case 'COMPLETED':
        color = const Color(0xFF9CA3AF);
        icon = Icons.sports_score_rounded;
        break;
      case 'CANCELLED':
        color = AppTheme.errorColor;
        icon = Icons.cancel_rounded;
        break;
      default:
        color = const Color(0xFF6B7280);
        icon = Icons.info_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opponent = match.opponent;
    final tierColor = AppTheme.tierColor(opponent.tier);
    // 내 스포츠 프로필 (해당 종목)
    final myProfiles = ref.watch(sportsProfilesProvider).valueOrNull ?? [];
    final myProfile = myProfiles.where((p) => p.sportType == match.sportType).toList();
    final mySportProfile = myProfile.isNotEmpty ? myProfile.first : null;
    final hasInfo = match.pinName != null ||
        match.desiredDate != null ||
        match.scheduledDate != null ||
        match.scheduledTime != null ||
        match.venueName != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF252525), width: 1),
      ),
      child: Column(
        children: [
          // ── 상단: 종목 + 타입 + 상태 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_sportIcon(match.sportType),
                          size: 14, color: AppTheme.primaryColor),
                      const SizedBox(width: 5),
                      Text(
                        match.sportTypeDisplayName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (match.isCasual) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '친선',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _buildStatusChip(match.status, match.statusDisplayName),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── VS 레이아웃 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 나
                Expanded(
                  child: Column(
                    children: [
                      Builder(builder: (context) {
                        final me = ref.watch(currentUserProvider);
                        final myTierColor = mySportProfile != null
                            ? AppTheme.tierColor(mySportProfile.tier)
                            : const Color(0xFF3A3A3A);
                        return Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: myTierColor.withOpacity(0.7),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: myTierColor.withOpacity(0.2),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: UserAvatar(
                            imageUrl: me?.profileImageUrl,
                            size: 64,
                            nickname: me?.nickname ?? '나',
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      Builder(builder: (context) {
                        final me = ref.watch(currentUserProvider);
                        return Text(
                          me?.nickname ?? '나',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        );
                      }),
                      _buildResultTag(match.gameResult, true),
                      if (mySportProfile != null && !mySportProfile.isPlacement) ...[
                        const SizedBox(height: 6),
                        Text(
                          mySportProfile.tier,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.tierColor(mySportProfile.tier),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // VS 배지
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Container(
                    width: 44,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withOpacity(0.2),
                          AppTheme.primaryDark.withOpacity(0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryColor,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),

                // 상대방
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tierColor.withOpacity(0.7),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tierColor.withOpacity(0.2),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: UserAvatar(
                          imageUrl: opponent.profileImageUrl,
                          size: 64,
                          nickname: opponent.nickname,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        opponent.nickname,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      _buildResultTag(match.gameResult, false),
                      if (!opponent.isPlacement) ...[
                        const SizedBox(height: 6),
                        Text(
                          opponent.tier,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tierColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── 점선 구분선 + 경기 정보 ──
          if (hasInfo) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const dashWidth = 5.0;
                  const dashSpace = 3.0;
                  final dashCount =
                      (constraints.maxWidth / (dashWidth + dashSpace)).floor();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      dashCount,
                      (i) => SizedBox(
                        width: dashWidth,
                        height: 1,
                        child: const DecoratedBox(
                          decoration:
                              BoxDecoration(color: Color(0xFF2A2A2A)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (match.pinName != null)
                    _InfoTile(
                      icon: Icons.location_on_rounded,
                      label: '핀',
                      value: match.pinName!,
                      iconColor: AppTheme.primaryColor,
                    ),
                  if (match.desiredDate != null) ...[
                    if (match.pinName != null) const SizedBox(height: 12),
                    _InfoTile(
                      icon: Icons.calendar_today_rounded,
                      label: '일시',
                      value: _formatMatchDateTime(
                          match.desiredDate, match.desiredTimeSlot),
                      iconColor: const Color(0xFF60A5FA),
                    ),
                  ],
                  if (match.scheduledDate != null) ...[
                    const SizedBox(height: 12),
                    _InfoTile(
                      icon: Icons.event_available_rounded,
                      label: '확정 날짜',
                      value: match.scheduledDate!,
                      iconColor: AppTheme.secondaryColor,
                    ),
                  ],
                  if (match.scheduledTime != null) ...[
                    const SizedBox(height: 12),
                    _InfoTile(
                      icon: Icons.schedule_rounded,
                      label: '확정 시간',
                      value: match.scheduledTime!,
                      iconColor: AppTheme.secondaryColor,
                    ),
                  ],
                  if (match.venueName != null) ...[
                    const SizedBox(height: 12),
                    _InfoTile(
                      icon: Icons.place_rounded,
                      label: '장소',
                      value: match.venueName!,
                      iconColor: const Color(0xFFA78BFA),
                    ),
                  ],
                  // 만남 횟수
                  const SizedBox(height: 12),
                  _InfoTile(
                    icon: Icons.people_rounded,
                    label: '만남',
                    value: match.encounterCount > 0
                        ? '${match.encounterCount}번째 만남'
                        : '첫 만남',
                    iconColor: match.encounterCount > 0
                        ? AppTheme.primaryColor
                        : const Color(0xFF34D399),
                  ),
                ],
              ),
            ),
          ],

          if (!hasInfo) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _InfoTile(
                    icon: Icons.emoji_events_rounded,
                    label: '상대 전적',
                    value: '${opponent.nickname} ${opponent.gamesPlayed}전 ${opponent.wins}승 ${opponent.losses}패 ${opponent.gamesPlayed - opponent.wins - opponent.losses}무',
                    iconColor: const Color(0xFFFBBF24),
                  ),
                  const SizedBox(height: 12),
                  _InfoTile(
                    icon: Icons.people_rounded,
                    label: '만남',
                    value: match.encounterCount > 0
                        ? '${match.encounterCount}번째 만남'
                        : '첫 만남',
                    iconColor: match.encounterCount > 0
                        ? AppTheme.primaryColor
                        : const Color(0xFF34D399),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 경기 정보 타일
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
