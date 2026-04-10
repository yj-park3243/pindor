import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/theme.dart';
import '../../providers/team_provider.dart';
import '../../widgets/common/app_toast.dart';

/// 팀 게시글 작성 화면
class TeamCreatePostScreen extends ConsumerStatefulWidget {
  final String teamId;

  const TeamCreatePostScreen({super.key, required this.teamId});

  @override
  ConsumerState<TeamCreatePostScreen> createState() =>
      _TeamCreatePostScreenState();
}

class _TeamCreatePostScreenState
    extends ConsumerState<TeamCreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  String _category = 'FREE';
  bool _isPinned = false;
  bool _isLoading = false;

  static const _categories = [
    {'key': 'FREE', 'label': '자유'},
    {'key': 'NOTICE', 'label': '공지'},
    {'key': 'SCHEDULE', 'label': '일정'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(teamPostsProvider(widget.teamId).notifier).createPost({
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'category': _category,
        'isPinned': _isPinned,
      });

      if (mounted) {
        AppToast.success('게시글이 작성되었습니다.');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('작성 실패: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글 작성'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('등록'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // ─── 카테고리 선택 ───
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF2A2A2A)),
                ),
              ),
              child: Row(
                children: [
                  ..._categories.map((cat) {
                    final isSelected = _category == cat['key'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat['label']!),
                        selected: isSelected,
                        onSelected: (_) =>
                            setState(() => _category = cat['key']!),
                        selectedColor: AppTheme.primaryColor,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }),
                  const Spacer(),
                  Row(
                    children: [
                      const Text(
                        '상단 고정',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      AdaptiveSwitch(
                        value: _isPinned,
                        onChanged: (v) => setState(() => _isPinned = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ─── 제목 ───
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: '제목을 입력하세요',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                maxLength: 60,
                buildCounter: (context,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '제목을 입력해주세요.';
                  return null;
                },
              ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // ─── 본문 ───
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: TextFormField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    hintText: '내용을 입력하세요',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '내용을 입력해주세요.';
                    return null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
