import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/game_repository.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/common/loading_indicator.dart';

/// 경기 결과 입력 화면 (PRD SCREEN-026)
class GameResultInputScreen extends ConsumerStatefulWidget {
  final String gameId;

  const GameResultInputScreen({super.key, required this.gameId});

  @override
  ConsumerState<GameResultInputScreen> createState() =>
      _GameResultInputScreenState();
}

/// 경기 결과 선택값
enum GameResult { win, draw, loss }

class _GameResultInputScreenState extends ConsumerState<GameResultInputScreen> {
  final List<String> _uploadedImageUrls = [];
  bool _isLoading = false;

  /// 선택된 경기 결과 (null = 미선택)
  GameResult? _selectedResult;

  /// 매너 점수 (1~5, 선택사항)
  int? _mannerScore;

  /// 게임 참가자 프로필 ID (서버에서 로드)
  String? _myProfileId;
  String? _opponentProfileId;
  bool _isLoadingGame = true;

  @override
  void initState() {
    super.initState();
    _loadGameData();
  }

  Future<void> _loadGameData() async {
    try {
      final repo = ref.read(gameRepositoryProvider);
      final game = await repo.getGameDetail(widget.gameId);
      final currentUser = ref.read(currentUserProvider);
      final currentUserId = currentUser?.id;

      if (mounted) {
        setState(() {
          // 현재 사용자가 requester인지 opponent인지 판별
          if (currentUserId != null &&
              game.requesterUserId == currentUserId) {
            _myProfileId = game.requesterProfileId;
            _opponentProfileId = game.opponentProfileId;
          } else {
            _myProfileId = game.opponentProfileId;
            _opponentProfileId = game.requesterProfileId;
          }
          _isLoadingGame = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGame = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('게임 정보 로드 실패: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_uploadedImageUrls.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 3장까지 첨부 가능합니다.')),
      );
      return;
    }

    final picker = ImagePicker();
    final remaining = 3 - _uploadedImageUrls.length;
    final images = await picker.pickMultiImage(imageQuality: 80);

    if (images.isEmpty) return;

    final selectedImages = images.take(remaining).toList();
    setState(() => _isLoading = true);

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final paths = selectedImages.map((img) => img.path).toList();
      final urls = await uploadRepo.uploadGameProofs(paths);

      setState(() => _uploadedImageUrls.addAll(urls));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 업로드 실패')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('경기 결과를 선택해주세요')),
      );
      return;
    }

    if (_myProfileId == null || _opponentProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('참가자 정보를 불러오지 못했습니다. 다시 시도해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(gameRepositoryProvider);

      // winnerId: 무승부이면 빈 문자열, 아니면 실제 프로필 ID
      final String winnerId;
      if (_selectedResult == GameResult.draw) {
        winnerId = ''; // 무승부
      } else if (_selectedResult == GameResult.win) {
        winnerId = _myProfileId!;
      } else {
        winnerId = _opponentProfileId!;
      }

      await repo.submitGameResult(
        widget.gameId,
        myResult: _selectedResult!.name.toUpperCase(),
        winnerId: winnerId,
        mannerScore: _mannerScore,
      );

      // 증빙 이미지가 있으면 서버에 전송
      if (_uploadedImageUrls.isNotEmpty) {
        await repo.uploadProofUrls(widget.gameId, _uploadedImageUrls);
      }

      if (mounted) {
        context.go('/games/${widget.gameId}/confirm');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingGame) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('경기 결과 입력'),
          backgroundColor: const Color(0xFFF8F9FA),
          elevation: 0,
        ),
        body: const FullScreenLoading(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('경기 결과 입력'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 배너
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF3FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.primaryColor, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '양측이 모두 결과를 입력하면 점수가 반영됩니다.\n불일치 시 이의 신청이 가능합니다.',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ─── 나의 경기 결과 선택 ───
            _SectionHeader(title: '나의 경기 결과'),
            const SizedBox(height: 4),
            const Text(
              '정확하게 입력해주세요. 허위 입력 시 불이익이 발생합니다.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ResultButton(
                    label: '승리',
                    icon: Icons.emoji_events_rounded,
                    isSelected: _selectedResult == GameResult.win,
                    selectedColor: AppTheme.secondaryColor,
                    onTap: () => setState(() => _selectedResult = GameResult.win),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ResultButton(
                    label: '무승부',
                    icon: Icons.handshake_rounded,
                    isSelected: _selectedResult == GameResult.draw,
                    selectedColor: Colors.grey.shade600,
                    onTap: () => setState(() => _selectedResult = GameResult.draw),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ResultButton(
                    label: '패배',
                    icon: Icons.sentiment_dissatisfied_rounded,
                    isSelected: _selectedResult == GameResult.loss,
                    selectedColor: AppTheme.errorColor,
                    onTap: () => setState(() => _selectedResult = GameResult.loss),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ─── 매너 점수 (선택) ───
            _SectionHeader(title: '매너 점수 (선택)'),
            const SizedBox(height: 6),
            const Text(
              '상대방의 매너는 어땠나요?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () => setState(() => _mannerScore = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      index < (_mannerScore ?? 0)
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Colors.amber,
                      size: 38,
                    ),
                  ),
                );
              }),
            ),
            if (_mannerScore != null) ...[
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _mannerScore = null),
                  child: const Text(
                    '평가 취소',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ─── 스코어카드 사진 업로드 ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionHeader(title: '스코어카드 사진'),
                Text(
                  '${_uploadedImageUrls.length}/3',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 사진 업로드 영역 (드래그 앤 드롭 스타일)
            if (_uploadedImageUrls.isEmpty && !_isLoading)
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      width: 1.5,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_rounded,
                        size: 36,
                        color: AppTheme.primaryColor.withOpacity(0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '사진을 탭하여 추가하세요',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryColor.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '최대 3장 첨부 가능',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ..._uploadedImageUrls.asMap().entries.map((entry) {
                    return Stack(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              entry.value,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() =>
                                  _uploadedImageUrls.removeAt(entry.key));
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  if (_uploadedImageUrls.length < 3)
                    GestureDetector(
                      onTap: _isLoading ? null : _pickImages,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: _isLoading
                            ? const Center(
                                child: LoadingIndicator(size: 20),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_rounded,
                                      size: 28,
                                      color: AppTheme.textSecondary),
                                  SizedBox(height: 4),
                                  Text(
                                    '추가',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '결과 제출',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class _ResultButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _ResultButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
