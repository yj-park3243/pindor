import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../repositories/support_repository.dart';
import '../common/app_toast.dart';
import '../../core/network/api_client.dart';

/// 신고 사유 목록
const _reportReasons = [
  ('MANNER', '비매너'),
  ('ABUSIVE', '욕설/혐오'),
  ('SPAM', '스팸'),
  ('OTHER', '기타'),
];

/// 신고 바텀시트
///
/// 사용 예:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => ReportBottomSheet(
///     targetType: 'POST',
///     targetId: post.id,
///   ),
/// );
/// ```
class ReportBottomSheet extends ConsumerStatefulWidget {
  /// 신고 대상 타입: USER | POST | COMMENT | CHAT | MATCH
  final String targetType;

  /// 신고 대상 ID
  final String targetId;

  const ReportBottomSheet({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  @override
  ConsumerState<ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends ConsumerState<ReportBottomSheet> {
  String? _selectedReason;
  final _descController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      AppToast.warning('신고 사유를 선택해주세요.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(supportRepositoryProvider).createReport(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: _selectedReason!,
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
          );

      if (mounted) {
        Navigator.of(context).pop();
        AppToast.success('신고가 접수되었습니다. 검토 후 처리됩니다.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '신고 접수에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들 바
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 타이틀
          const Text(
            '신고하기',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '신고 사유를 선택해주세요.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // 사유 라디오 목록
          ..._reportReasons.map((reason) {
            return RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: reason.$1,
              groupValue: _selectedReason,
              onChanged: (v) => setState(() => _selectedReason = v),
              title: Text(
                reason.$2,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              activeColor: AppTheme.primaryColor,
              dense: true,
            );
          }),

          const SizedBox(height: 12),

          // 상세 내용 입력 (선택)
          TextField(
            controller: _descController,
            maxLines: 3,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: '추가 내용을 입력해주세요 (선택)',
              labelText: '상세 내용',
            ),
          ),

          const SizedBox(height: 16),

          // 제출 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('신고 접수'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 신고 바텀시트를 편하게 호출하는 헬퍼 함수
void showReportBottomSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReportBottomSheet(
      targetType: targetType,
      targetId: targetId,
    ),
  );
}
