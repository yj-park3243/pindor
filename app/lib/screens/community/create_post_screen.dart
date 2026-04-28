import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/permission_helper.dart';
import '../../providers/community_provider.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/common/app_toast.dart';

/// 게시글 작성 화면
class CreatePostScreen extends ConsumerStatefulWidget {
  final String pinId;
  final String sportType;

  const CreatePostScreen({super.key, required this.pinId, required this.sportType});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final List<File> _pickedImages = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_pickedImages.length >= 4) {
      AppToast.warning('이미지는 최대 4장까지 첨부할 수 있습니다.');
      return;
    }

    if (!mounted) return;

    final picker = ImagePicker();
    final xFiles = await picker.pickMultiImage(imageQuality: 80);
    if (xFiles.isEmpty) return;

    final remaining = 4 - _pickedImages.length;
    final toAdd = xFiles.take(remaining).map((f) => File(f.path)).toList();
    setState(() => _pickedImages.addAll(toAdd));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      List<String> imageUrls = [];
      if (_pickedImages.isNotEmpty) {
        final uploadRepo = ref.read(uploadRepositoryProvider);
        final uploadTasks =
            _pickedImages.map((file) => uploadRepo.uploadPostImage(file.path));
        imageUrls = await Future.wait(uploadTasks);
      }

      await ref.read(communityRepositoryProvider).createPost(
            pinId: widget.pinId,
            title: _titleController.text.trim(),
            content: _contentController.text.trim(),
            sportType: widget.sportType,
            imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
          );

      if (mounted) {
        AppToast.success('게시글이 등록되었습니다!');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '게시글 작성에 실패했습니다.';
        if (e is ApiException) {
          errorMessage = e.message;
        }
        AppToast.error(errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('게시글 작성'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '등록',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 종목 태그 (고정)
              Builder(builder: (_) {
                final sport = allSports.where((s) => s.value == widget.sportType).firstOrNull ?? allSports.first;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(sport.icon, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        sport.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              // 제목
              const Text(
                '제목',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '제목을 입력하세요',
                  hintStyle: const TextStyle(color: AppTheme.textDisabled),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLength: 100,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '제목을 입력해주세요.';
                  if (v.trim().length < 2) return '제목은 2자 이상이어야 합니다.';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 내용
              const Text(
                '내용',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contentController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '내용을 입력하세요...',
                  hintStyle: const TextStyle(color: AppTheme.textDisabled),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  alignLabelWithHint: true,
                ),
                maxLines: 10,
                minLines: 6,
                maxLength: 2000,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '내용을 입력해주세요.';
                  if (v.trim().length < 5) return '내용은 5자 이상이어야 합니다.';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 이미지 첨부
              const Text(
                '사진 첨부 (선택, 최대 4장)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _ImagePicker(
                images: _pickedImages,
                onAdd: _pickImage,
                onRemove: (index) =>
                    setState(() => _pickedImages.removeAt(index)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePicker extends StatelessWidget {
  final List<File> images;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  const _ImagePicker({
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        scrollDirection: Axis.horizontal,
        children: [
          if (images.length < 4)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF3A3A3A), width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        color: AppTheme.textSecondary),
                    Text(
                      '${images.length}/4',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textDisabled),
                    ),
                  ],
                ),
              ),
            ),
          ...images.asMap().entries.map((entry) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    image: DecorationImage(
                      image: FileImage(entry.value),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemove(entry.key),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
