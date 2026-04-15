import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../models/match.dart';
import '../../providers/matching_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/matching_repository.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../core/network/socket_service.dart';

/// 매칭 수락 화면 (PENDING_ACCEPT 상태)
/// - 서버에서 직접 매칭 데이터를 가져옴 (SWR 로컬 캐시 우회)
/// - 10분 카운트다운 타이머 (서버의 expiresAt 기준)
/// - 수락 → 상대 응답 대기
/// - 양측 수락 시 채팅 화면으로 자동 이동
/// - 거절 → 토스트 + 목록 이동
/// - PopScope로 뒤로가기 차단 (매칭 잠금)
class MatchAcceptScreen extends ConsumerStatefulWidget {
  final String matchId;

  const MatchAcceptScreen({super.key, required this.matchId});

  @override
  ConsumerState<MatchAcceptScreen> createState() => _MatchAcceptScreenState();
}

class _MatchAcceptScreenState extends ConsumerState<MatchAcceptScreen> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _hasAccepted = false; // 내가 수락 버튼을 눌렀는지
  bool _timerStarted = false;
  bool _isNavigating = false; // 중복 네비게이션 방지
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  // 서버에서 직접 가져온 매칭 데이터 (SWR 우회)
  Match? _match;
  bool _isLoading = true;
  String? _loadError;

  // 총 타이머 시간 — 10분 기준 (요구사항)
  static const Duration _totalDuration = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _fetchMatchFromServer();
    _listenMatchStatus();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// 소켓으로 매칭 상태 변경 직접 감지 (CANCELLED → 목록으로 이동)
  void _listenMatchStatus() {
    _statusSub = SocketService.instance.onMatchStatusChanged.listen((data) {
      final matchId = data['matchId'] as String?;
      final status = data['status'] as String?;
      if (matchId != widget.matchId) return;

      if (status == 'CANCELLED' && mounted && !_isNavigating) {
        _isNavigating = true;
        _countdownTimer?.cancel();
        AppToast.info('상대방이 매칭을 취소했습니다.');
        ref.invalidate(matchListProvider(null));
        context.go(AppRoutes.matchList);
      }
    });
  }

  /// 서버에서 직접 매칭 데이터 가져오기 (SWR 로컬 캐시 우회)
  Future<void> _fetchMatchFromServer() async {
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final match = await repo.getMatchDetail(widget.matchId);
      if (!mounted) return;

      // 이미 수락했거나, PENDING_ACCEPT이 아니거나, 만료됐으면 → 매칭 목록으로
      final alreadyAccepted = match.acceptances?.any((a) => a.accepted == true) ?? false;
      final isExpired = match.acceptances?.any((a) =>
          a.expiresAt != null && a.expiresAt!.isBefore(DateTime.now())) ?? false;

      if (alreadyAccepted || !match.isPendingAccept || isExpired) {
        ref.invalidate(matchListProvider(null));
        context.go(AppRoutes.matchList);
        return;
      }

      setState(() {
        _match = match;
        _isLoading = false;
      });
      _startCountdown(match);
    } catch (e) {
      debugPrint('[MatchAccept] Server fetch failed: $e');
      if (!mounted) return;
      final is404 = e.toString().contains('MATCH_002') ||
          e.toString().contains('404') ||
          e.toString().contains('찾을 수 없');
      if (is404) {
        // 매칭 없음 (만료/삭제) → 캐시 정리 후 목록 이동
        ref.read(matchingRepositoryProvider).clearLocalCache();
        ref.invalidate(matchListProvider(null));
        context.go(AppRoutes.matchList);
      } else {
        // 서버 에러 (500 등) → 에러 화면 표시, 재시도 가능
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  void _startCountdown(Match match) {
    if (_timerStarted) return;
    _timerStarted = true;

    // expiresAt이 있는 acceptances에서 만료 시각 가져오기
    // 없으면 현재로부터 10분 후 기본값 사용
    DateTime? expiresAt;
    if (match.acceptances != null && match.acceptances!.isNotEmpty) {
      final myId = ref.read(currentUserProvider)?.id;
      final myAcceptance = match.acceptances!
          .where((a) => a.userId == myId)
          .firstOrNull;
      expiresAt = myAcceptance?.expiresAt ?? match.acceptances!.first.expiresAt;
    }
    // fallback: 서버 expiresAt이 없으면 매칭 생성 시각 + 10분 (로컬 타이머 생성 방지)
    if (expiresAt == null) {
      expiresAt = match.createdAt.add(_totalDuration);
      debugPrint('[Timer] expiresAt not found from server, using fallback: $expiresAt');
    }

    _countdownTimer?.cancel();
    _updateRemaining(expiresAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining(expiresAt!);
    });
  }

  void _updateRemaining(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      _countdownTimer?.cancel();
      setState(() => _remaining = Duration.zero);
      if (mounted && !_isNavigating) {
        _isNavigating = true;
        _showToast('매칭 수락 시간이 만료되었습니다.');
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            ref.invalidate(matchListProvider(null));
            context.go(AppRoutes.matchList);
          }
        });
      }
    } else {
      setState(() => _remaining = remaining);
    }
  }

  double get _progressRatio {
    final total = _totalDuration.inSeconds;
    final remaining = _remaining.inSeconds;
    if (total == 0) return 0;
    return (remaining / total).clamp(0.0, 1.0);
  }

  String get _timerText {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _onAccept() async {
    final notifier = ref.read(matchAcceptProvider(widget.matchId).notifier);
    final success = await notifier.acceptMatch();
    if (!mounted) return;

    if (success) {
      final acceptState = ref.read(matchAcceptProvider(widget.matchId));
      if (acceptState.acceptStatus == 'MATCHED') {
        // 양측 수락 완료 → 축하 토스트 후 매칭 상세 화면으로 이동
        if (_isNavigating) return;
        _isNavigating = true;
        AppToast.success('매칭이 확정되었습니다! 🎉');
        ref.invalidate(matchListProvider(null));
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          context.go('/matches/${widget.matchId}');
        });
      } else {
        // 상대 응답 대기 → 매칭 진행중 목록으로 이동
        ref.invalidate(matchListProvider(null));
        context.go(AppRoutes.matchList);
      }
    } else {
      final error = ref.read(matchAcceptProvider(widget.matchId)).error ?? '';
      _showToast('오류: $error');
    }
  }

  Future<void> _onReject() async {
    // 거절 재확인 다이얼로그
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
              child: Icon(Icons.thumb_down_outlined,
                  color: AppTheme.errorColor, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              '매칭 거절',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '거절하면 -15점 패널티가 적용됩니다.\n정말 거절하시겠습니까?',
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
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('거절하기',
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

    if (confirmed != true || !mounted) return;

    final notifier = ref.read(matchAcceptProvider(widget.matchId).notifier);
    final success = await notifier.rejectMatch();
    if (!mounted) return;

    if (success) {
      _isNavigating = true;
      _showToast('매칭이 거절되었습니다. (-15점)');
      context.go(AppRoutes.matchList);
    } else {
      final error = ref.read(matchAcceptProvider(widget.matchId)).error ?? '';
      // 쿨다운 에러 메시지 처리 (서버에서 내려오는 형태 그대로 표시)
      _showToast(error.isNotEmpty ? error : '거절 처리 중 오류가 발생했습니다.');
    }
  }

  /// 날짜 문자열 포맷 (ISO → "4월 10일 (오늘)" 형태)
  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      // "2026-04-10" 또는 "2026-04-10T00:00:00.000Z" → 날짜만 파싱
      final dateStr = raw.length >= 10 ? raw.substring(0, 10) : raw;
      final parts = dateStr.split('-');
      if (parts.length != 3) return dateStr;
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final date = DateTime(year, month, day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      String suffix = '';
      if (date == today) {
        suffix = ' (오늘)';
      } else if (date == tomorrow) {
        suffix = ' (내일)';
      }
      return '${month}월 ${day}일$suffix';
    } catch (_) {
      return raw;
    }
  }

  void _showToast(String message) {
    AppToast.info(message);
  }

  @override
  Widget build(BuildContext context) {
    final acceptState = ref.watch(matchAcceptProvider(widget.matchId));

    // 소켓/폴링 상태 변경 감지
    ref.listen<MatchAcceptState>(
      matchAcceptProvider(widget.matchId),
      (prev, next) {
        // 상대가 거절하거나 타임아웃된 경우 (CANCELLED)
        if (prev?.acceptStatus != 'CANCELLED' &&
            next.acceptStatus == 'CANCELLED' &&
            mounted &&
            !_isNavigating) {
          _isNavigating = true;
          // 내가 거절한 경우(_onReject)는 별도 처리하므로, 상대 거절/타임아웃만 여기서 처리
          // _hasAccepted 여부와 무관하게 소켓/폴링으로 온 CANCELLED는 상대 측 이벤트
          _showToast('상대방이 매칭을 거절했습니다.');
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              ref.invalidate(matchListProvider(null));
              context.go(AppRoutes.matchList);
            }
          });
        }

        // 양측 수락 완료 → CHAT 상태로 전환 (소켓/폴링 경로) → 매칭 상세 화면으로 이동
        if (prev?.updatedMatch?.status != 'CHAT' &&
            next.updatedMatch?.status == 'CHAT' &&
            mounted &&
            !_isNavigating) {
          _isNavigating = true;
          AppToast.success('매칭이 확정되었습니다! 🎉');
          ref.invalidate(matchListProvider(null));
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!mounted) return;
            context.go('/matches/${widget.matchId}');
          });
        }
      },
    );

    // 로딩 중
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(child: LoadingIndicator(size: 32)),
      );
    }

    // 서버 에러 (500 등) → 재시도 가능한 에러 화면
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              const Text('매칭 정보를 불러올 수 없습니다', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() { _isLoading = true; _loadError = null; });
                  _fetchMatchFromServer();
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                child: const Text('다시 시도'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  ref.read(matchingRepositoryProvider).clearLocalCache();
                  ref.invalidate(matchListProvider(null));
                  context.go(AppRoutes.matchList);
                },
                child: const Text('매칭 목록으로 돌아가기', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
      );
    }

    final match = _match!;

    return PopScope(
      canPop: false, // 뒤로가기 차단 — 매칭 화면 잠금
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Builder(builder: (context) {
            final timerColor = _remaining.inMinutes >= 5
                ? AppTheme.primaryColor
                : _remaining.inMinutes >= 2
                    ? AppTheme.warningColor
                    : AppTheme.errorColor;
            final encounterText = match.encounterCount > 0
                ? '${match.encounterCount}번 만난 상대'
                : '처음 만나는 상대';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // ─── 스크롤 영역: 상대 정보 + 매칭 정보 ───
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 16),

                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.sports_rounded, size: 24, color: AppTheme.primaryColor),
                                SizedBox(width: 8),
                                Text(
                                  '매칭이 잡혔습니다!',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.primaryColor),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // 프로필 이미지
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4), width: 2.5),
                              ),
                              child: match.opponent.profileImageUrl != null
                                  ? ClipOval(child: Image.network(match.opponent.profileImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 44, color: AppTheme.primaryColor)))
                                  : const Icon(Icons.person_rounded, size: 44, color: AppTheme.primaryColor),
                            ),
                            const SizedBox(height: 16),

                            // 닉네임
                            Text(match.opponent.nickname, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),

                            // 프로필 메시지 (닉네임 바로 아래)
                            if (match.opponent.matchMessage != null && match.opponent.matchMessage!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '"${match.opponent.matchMessage!}"',
                                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),

                            // 등급 + 점수 + 경기수
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!match.opponent.isPlacement) ...[
                                  Text(
                                    match.opponent.tier,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.tierColor(match.opponent.tier),
                                    ),
                                  ),
                                  const Text(' · ', style: TextStyle(color: AppTheme.textDisabled)),
                                ],
                                Text(
                                  match.opponent.isPlacement ? '배치 중' : '${match.opponent.displayScore ?? match.opponent.currentScore ?? 1000}점',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                                ),
                                if (match.opponent.gamesPlayed > 0) ...[
                                  const Text(' · ', style: TextStyle(color: AppTheme.textDisabled)),
                                  Text('${match.opponent.gamesPlayed}경기', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),

                            // 만남 횟수
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(match.encounterCount > 0 ? Icons.repeat_rounded : Icons.waving_hand_rounded, size: 14, color: AppTheme.textSecondary),
                                const SizedBox(width: 4),
                                Text(encounterText, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // ─── 매칭 정보 카드 ───
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF2A2A2A)),
                              ),
                              child: Column(
                                children: [
                                  // 핀 + 종목 + 랭크/친선
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_rounded, size: 18, color: AppTheme.primaryColor),
                                      const SizedBox(width: 6),
                                      Text(match.pinName ?? '핀 정보 없음', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                                        child: Text(match.sportTypeDisplayName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: match.isCasual ? Colors.orange.withOpacity(0.12) : Colors.blue.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(match.isCasual ? '친선' : '랭크', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: match.isCasual ? Colors.orange : Colors.blue)),
                                      ),
                                    ],
                                  ),
                                  if (match.desiredDate != null || match.scheduledDate != null) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Icon(Icons.schedule_rounded, size: 16, color: AppTheme.textSecondary),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${_formatDate(match.desiredDate ?? match.scheduledDate)}${match.desiredTimeSlot != null ? ' · ${match.desiredTimeSlotDisplayName}' : ''}',
                                          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                  // 프로필 메시지는 상단 닉네임 아래로 이동
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ─── 하단 고정: 타이머 + 버튼 ───
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer_outlined, size: 16, color: timerColor),
                        const SizedBox(width: 6),
                        Text(_timerText, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: timerColor, fontFeatures: const [FontFeature.tabularFigures()])),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: _progressRatio, minHeight: 5, backgroundColor: const Color(0xFF2A2A2A), valueColor: AlwaysStoppedAnimation<Color>(timerColor)),
                    ),
                    const SizedBox(height: 16),

                    if (_hasAccepted)
                      const _WaitingForOpponent()
                    else
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: acceptState.isLoading ? null : _onReject,
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                child: const Text('거절 (-15점)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: acceptState.isLoading ? null : _onAccept,
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                child: acceptState.isLoading
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                    : const Text('수락', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          }),
      ),
    );
  }
}

// ─── 매칭 성사 헤더 ───
class _MatchSuccessHeader extends StatelessWidget {
  const _MatchSuccessHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.sports_rounded,
            size: 32,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '대결 상대가 나타났습니다!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '10분 내로 수락 여부를 결정해주세요.',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── 상대 프로필 카드 (닉네임 / 랭킹 / 종목) ───
class _OpponentCard extends StatelessWidget {
  final MatchOpponent opponent;
  final String? pinName;
  final int encounterCount;

  const _OpponentCard({
    required this.opponent,
    this.pinName,
    this.encounterCount = 0,
  });

  /// 배치 중 여부에 따라 랭킹 텍스트 반환
  String get _rankText {
    if (opponent.isPlacement) return '배치';
    return '${opponent.displayScore ?? opponent.currentScore ?? 1000}점';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── 상대방 정보 라벨 ───
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '상대방 정보',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 프로필 아이콘
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4), width: 2.5),
            ),
            child: opponent.profileImageUrl != null
                ? ClipOval(
                    child: Image.network(
                      opponent.profileImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
          ),
          const SizedBox(height: 16),

          // 닉네임
          Text(
            opponent.nickname,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),

          // 랭킹 / 종목 정보
          _InfoRow(
            items: [
              _InfoItem(
                label: '종목',
                value: _sportDisplayName(opponent.sportType),
              ),
              _InfoItem(
                label: '점수',
                value: _rankText,
                valueColor: opponent.isPlacement
                    ? AppTheme.textSecondary
                    : AppTheme.primaryColor,
              ),
              if (opponent.gamesPlayed > 0)
                _InfoItem(
                  label: '경기',
                  value: '${opponent.gamesPlayed}',
                ),
            ],
          ),

          const SizedBox(height: 16),

          // 핀 지역 + 만남 횟수
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // 핀 지역
                if (pinName != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 15, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        pinName!,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // 만남 횟수
                Row(
                  children: [
                    Icon(
                      encounterCount > 0 ? Icons.people_rounded : Icons.person_add_rounded,
                      size: 15,
                      color: encounterCount > 0 ? const Color(0xFF10B981) : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      encounterCount > 0
                          ? '$encounterCount번 만난 상대입니다'
                          : '처음 보는 상대입니다',
                      style: TextStyle(
                        fontSize: 13,
                        color: encounterCount > 0 ? const Color(0xFF10B981) : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                // 매칭 문구
                if (opponent.matchMessage != null && opponent.matchMessage!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '"${opponent.matchMessage!}"',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sportDisplayName(String sportType) {
    switch (sportType) {
      case 'GOLF': return '골프';
      case 'BILLIARDS': return '당구';
      case 'TENNIS': return '테니스';
      case 'TABLE_TENNIS': return '탁구';
      default: return sportType;
    }
  }
}

class _InfoItem {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoItem({
    required this.label,
    required this.value,
    this.valueColor,
  });
}

class _InfoRow extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.expand((item) sync* {
        yield _InfoCell(item: item);
        if (item != items.last) {
          yield Container(
            width: 1,
            height: 30,
            color: const Color(0xFF2A2A2A),
          );
        }
      }).toList(),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final _InfoItem item;

  const _InfoCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          item.value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: item.valueColor ?? AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── 타이머 섹션 ───
class _TimerSection extends StatelessWidget {
  final String timerText;
  final double progressRatio;
  final Duration remaining;

  const _TimerSection({
    required this.timerText,
    required this.progressRatio,
    required this.remaining,
  });

  Color get _timerColor {
    if (remaining.inMinutes >= 10) return AppTheme.primaryColor;
    if (remaining.inMinutes >= 5) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 18, color: _timerColor),
            const SizedBox(width: 6),
            Text(
              '남은 시간: ',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              timerText,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _timerColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progressRatio,
            minHeight: 8,
            backgroundColor: const Color(0xFF2A2A2A),
            valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
          ),
        ),
      ],
    );
  }
}

// ─── 수락/거절 버튼 ───
class _AcceptRejectButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _AcceptRejectButtons({
    required this.isLoading,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 거절 버튼 — 빨간색, -15점 패널티 표시
        Expanded(
          child: ElevatedButton(
            onPressed: isLoading ? null : onReject,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '거절',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '(-15점)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 수락 버튼 — 파란색/초록색
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: isLoading ? null : onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '수락',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── 수락 후 대기 화면 ───
class _WaitingForOpponent extends StatelessWidget {
  const _WaitingForOpponent();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '상대의 응답을 기다리고 있습니다...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '상대방이 수락하면 채팅이 시작됩니다.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
