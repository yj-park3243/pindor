import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../core/network/api_client.dart';
import '../../providers/community_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/common/app_toast.dart';

/// 게시글 작성 화면
class CreatePostScreen extends ConsumerStatefulWidget {
  final String pinId;

  const CreatePostScreen({super.key, required this.pinId});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late String _selectedSport;
  final List<File> _pickedImages = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedSport = ref.read(sportPreferenceProvider);
  }

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
            sportType: _selectedSport,
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
      appBar: AppBar(
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 스포츠 선택 (가로 스크롤 칩)
              const Text(
                '종목',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: allSports.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final sport = allSports[index];
                    final isSelected = _selectedSport == sport.value;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedSport = sport.value);
                        ref
                            .read(sportPreferenceProvider.notifier)
                            .select(sport.value);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : const Color(0xFFE0E3E8),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              sport.icon,
                              size: 16,
                              color:
                                  isSelected ? Colors.white : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sport.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
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
                decoration: const InputDecoration(
                  hintText: '제목을 입력하세요',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  hintText: '내용을 입력하세요...',
                  border: OutlineInputBorder(),
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
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
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
