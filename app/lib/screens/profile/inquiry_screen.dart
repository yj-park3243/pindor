import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../repositories/support_repository.dart';

/// 문의 카테고리 옵션
const _inquiryCategories = [
  ('ACCOUNT', '계정'),
  ('MATCH', '매칭'),
  ('SCORE', '점수/랭크'),
  ('BUG', '버그 신고'),
  ('SUGGESTION', '개선 제안'),
  ('OTHER', '기타'),
];

/// 문의 상태 표시
const _statusLabels = {
  'PENDING': '검토 중',
  'IN_PROGRESS': '처리 중',
  'RESOLVED': '해결됨',
  'CLOSED': '종료',
};

/// 내 문의 목록 프로바이더
final myInquiriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.read(supportRepositoryProvider).getMyInquiries();
});

/// 문의하기 화면 (PRD 4b)
class InquiryScreen extends ConsumerStatefulWidget {
  const InquiryScreen({super.key});

  @override
  ConsumerState<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends ConsumerState<InquiryScreen> {
  String _selectedCategory = 'ACCOUNT';
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문의 제목을 입력해주세요.')),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문의 내용을 입력해주세요.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(supportRepositoryProvider).createInquiry(
            category: _selectedCategory,
            title: title,
            content: content,
          );

      if (mounted) {
        _titleController.clear();
        _contentController.clear();
        setState(() => _selectedCategory = 'ACCOUNT');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('문의가 접수되었습니다. 빠른 시일 내에 답변 드리겠습니다.'),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );

        // 목록 갱신
        ref.invalidate(myInquiriesProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('문의 접수에 실패했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inquiriesAsync = ref.watch(myInquiriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('문의하기'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 문의 작성 카드 ───
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '새 문의',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 카테고리 드롭다운
                  const Text(
                    '문의 유형',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    items: _inquiryCategories
                        .map((cat) => DropdownMenuItem(
                              value: cat.$1,
                              child: Text(cat.$2),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCategory = v);
                    },
                  ),

                  const SizedBox(height: 14),

                  // 제목
                  const Text(
                    '제목',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleController,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      hintText: '문의 제목을 입력해주세요',
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 내용
                  const Text(
                    '내용',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _contentController,
                    maxLines: 6,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: '문의 내용을 자세히 입력해주세요',
                      alignLabelWithHint: true,
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('문의 접수'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ─── 내 문의 목록 ───
            const Text(
              '내 문의 내역',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            inquiriesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    '문의 내역을 불러올 수 없습니다.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),
              data: (inquiries) {
                if (inquiries.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        '접수된 문의가 없습니다.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  );
                }

                return Column(
                  children: inquiries.map((inquiry) {
                    return _InquiryTile(inquiry: inquiry);
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// 개별 문의 항목 타일
class _InquiryTile extends StatelessWidget {
  final Map<String, dynamic> inquiry;

  const _InquiryTile({required this.inquiry});

  @override
  Widget build(BuildContext context) {
    final status = inquiry['status'] as String? ?? 'PENDING';
    final statusLabel = _statusLabels[status] ?? status;
    final title = inquiry['title'] as String? ?? '';
    final category = inquiry['category'] as String? ?? '';
    final categoryLabel = _inquiryCategories
        .firstWhere(
          (c) => c.$1 == category,
          orElse: () => (category, category),
        )
        .$2;

    final createdAtStr = inquiry['createdAt'] as String?;
    String dateStr = '';
    if (createdAtStr != null) {
      try {
        final dt = DateTime.parse(createdAtStr);
        dateStr = DateFormat('yyyy.MM.dd').format(dt);
      } catch (_) {}
    }

    Color statusColor;
    switch (status) {
      case 'RESOLVED':
        statusColor = AppTheme.secondaryColor;
        break;
      case 'IN_PROGRESS':
        statusColor = AppTheme.primaryColor;
        break;
      case 'CLOSED':
        statusColor = AppTheme.textDisabled;
        break;
      default:
        statusColor = AppTheme.warningColor;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 카테고리 칩
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  categoryLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const Spacer(),
              // 상태 칩
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (dateStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textDisabled,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
