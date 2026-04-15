import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../config/theme.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/permission_helper.dart';
import '../../providers/user_provider.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/app_toast.dart';

/// 프로필 수정 화면 (PRD SCREEN-061)
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  File? _newProfileImage;
  bool _isSaving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _initializeIfNeeded(dynamic user) {
    if (_initialized || user == null) return;
    _nicknameController.text = user.nickname;
    _initialized = true;
  }

  Future<void> _pickImage() async {
    if (!mounted) return;

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (xFile != null) {
      setState(() => _newProfileImage = File(xFile.path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // 이전 프로필 이미지 URL 기억 (캐시 제거용)
      final currentUser = ref.read(userNotifierProvider).valueOrNull;
      final oldImageUrl = currentUser?.profileImageUrl;

      String? profileImageUrl;
      if (_newProfileImage != null) {
        final uploadRepo = ref.read(uploadRepositoryProvider);
        profileImageUrl = await uploadRepo.uploadProfileImage(_newProfileImage!.path);
      }

      await ref.read(userNotifierProvider.notifier).updateProfile(
            nickname: _nicknameController.text.trim(),
            profileImageUrl: profileImageUrl,
          );

      // 이전 이미지 캐시 제거 후 최신 유저 상태 재조회
      if (oldImageUrl != null) {
        await CachedNetworkImage.evictFromCache(oldImageUrl);
      }
      if (profileImageUrl != null) {
        await CachedNetworkImage.evictFromCache(profileImageUrl);
      }
      ref.invalidate(userNotifierProvider);

      if (mounted) {
        AppToast.success('프로필이 수정되었습니다.');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '프로필 수정에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 수정'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '저장',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (user) {
          _initializeIfNeeded(user);
          if (user == null) return const SizedBox();

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 프로필 사진
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: _newProfileImage != null
                                ? Image.file(_newProfileImage!, fit: BoxFit.cover)
                                : user.profileImageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: user.profileImageUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 192,
                                        memCacheHeight: 192,
                                      )
                                    : Container(
                                        color: AppTheme.primaryColor.withOpacity(0.2),
                                        child: Center(
                                          child: Text(
                                            user.nickname.isNotEmpty
                                                ? user.nickname[0]
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ),
                                      ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '사진 변경',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.primaryColor,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 닉네임
                  TextFormField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      labelText: '닉네임',
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    maxLength: 20,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return '닉네임을 입력해주세요.';
                      }
                      if (v.trim().length < 2) {
                        return '닉네임은 2자 이상이어야 합니다.';
                      }
                      if (v.trim().length > 20) {
                        return '닉네임은 20자 이하여야 합니다.';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // 이메일 (수정 불가)
                  if (user.email != null)
                    TextFormField(
                      initialValue: user.email,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: '이메일',
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.email_outlined),
                        helperText: '이메일은 변경할 수 없습니다.',
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
