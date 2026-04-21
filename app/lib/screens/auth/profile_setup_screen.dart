import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/permission_helper.dart';
import '../../repositories/upload_repository.dart';
import '../../repositories/user_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_toast.dart';

/// 닉네임/프로필 이미지 설정 화면 (신규 가입 플로우)
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _profileImageUrl;
  bool _isLoading = false;
  bool _isImageLoading = false;
  String? _nicknameError;
  bool _agreedToTerms = false;
  bool _agreedToPrivacy = false;

  static const _adjectives = [
    // 속도/힘
    '빠른', '날쌘', '강한', '거친', '묵직한', '터프한', '민첩한', '재빠른', '힘센', '단단한',
    // 온도/에너지
    '뜨거운', '화끈한', '냉철한', '차가운', '불타는', '얼음', '번개', '불꽃', '폭풍', '천둥',
    // 성격/태도
    '용감한', '대담한', '무서운', '당당한', '끈질긴', '집요한', '고요한', '침착한', '야생의', '자유로운',
    // 수식어
    '무적의', '전설의', '최강', '미친', '압도적', '극한', '치명적', '완벽한', '정밀한', '핵폭탄',
    // 느낌/분위기
    '멋진', '빛나는', '어둠의', '새벽', '황금', '다크', '실버', '크림슨', '코발트', '네온',
    // 동작
    '돌진', '질풍', '파워', '슈퍼', '울트라', '터보', '하이퍼', '매직', '로켓', '미사일',
    // 자연
    '태풍', '회오리', '지진', '화산', '쓰나미', '혜성', '유성', '오로라', '섬광', '벼락',
    // 스포츠
    '에이스', '올스타', '클러치', '매치포인트', '역전의', '결승골', '홈런', '스매시', '드리블', '스윙',
  ];

  static const _nouns = [
    // 맹수
    '호랑이', '사자', '치타', '표범', '늑대', '곰', '황소', '재규어', '퓨마', '코브라',
    // 날짐승
    '독수리', '매', '콘도르', '올빼미', '까마귀', '봉황', '팔콘', '호크', '까치', '펭귄',
    // 바다
    '상어', '고래', '돌고래', '문어', '바라쿠다', '가오리', '해파리', '범고래', '참치', '피라냐',
    // 판타지
    '드래곤', '피닉스', '타이탄', '고렘', '그리핀', '유니콘', '크라켄', '케르베로스', '미노타우르', '발키리',
    // 전사/역할
    '워리어', '챔피언', '히어로', '헌터', '파이터', '레전드', '가디언', '나이트', '바이킹', '검투사',
    // 스포츠
    '스트라이커', '캡틴', '에이스', '골키퍼', '타자', '투수', '센터', '슈터', '서버', '러너',
    // 기타
    '킹', '마스터', '보스', '제왕', '황제', '폭격기', '전차', '스나이퍼', '라이더', '스톰',
    // 추가
    '해적', '닌자', '사무라이', '기사', '궁수', '마법사', '연금술사', '조커', '팬텀', '블레이드',
  ];

  @override
  void initState() {
    super.initState();
    _generateRandomNickname();
  }

  Future<void> _generateRandomNickname() async {
    final rng = Random();
    final adj = _adjectives[rng.nextInt(_adjectives.length)];
    final noun = _nouns[rng.nextInt(_nouns.length)];
    var candidate = '$adj$noun';

    // 중복 체크 → 중복이면 숫자 붙이기
    for (var i = 0; i < 10; i++) {
      try {
        final response = await ApiClient.instance.get(
          '/users/check-nickname',
          queryParameters: {'nickname': candidate},
        );
        final available = response['data']?['available'] as bool? ?? false;
        if (available) break;
        candidate = '$adj$noun${i + 1}';
      } catch (_) {
        break;
      }
    }

    if (mounted) {
      _nicknameController.text = candidate;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (!mounted) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (image == null) return;

    setState(() => _isImageLoading = true);
    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final url = await uploadRepo.uploadProfileImage(image.path);
      setState(() => _profileImageUrl = url);
    } catch (e) {
      if (mounted) {
        AppToast.error('이미지 업로드 실패');
      }
    } finally {
      if (mounted) setState(() => _isImageLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _nicknameError = null;
    });

    try {
      // 제출 시 닉네임 중복 확인
      final nickname = _nicknameController.text.trim();
      final checkResponse = await ApiClient.instance.get(
        '/users/check-nickname',
        queryParameters: {'nickname': nickname},
      );
      final available = checkResponse['data']?['available'] as bool? ?? false;

      if (!available) {
        setState(() {
          _isLoading = false;
          _nicknameError = '이미 사용 중인 닉네임입니다.';
        });
        if (mounted) {
          AppToast.warning('이미 사용 중인 닉네임입니다.');
        }
        return;
      }

      final userRepo = ref.read(userRepositoryProvider);
      final user = await userRepo.updateProfile(
        nickname: nickname,
        profileImageUrl: _profileImageUrl,
      );

      ref.read(authStateProvider.notifier).updateUser(user);

      if (mounted) context.go(AppRoutes.fontSizeSetup);
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.code == 'NICKNAME_TAKEN') {
        setState(() => _nicknameError = '이미 사용 중인 닉네임입니다.');
        if (mounted) {
          AppToast.warning('이미 사용 중인 닉네임입니다.');
        }
      } else {
        debugPrint('[ProfileSetup] _submit ApiException: $e');
        if (mounted) {
          AppToast.error('프로필 저장 실패: ${e.message}');
        }
      }
    } catch (e) {
      debugPrint('[ProfileSetup] _submit 에러: $e');
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '프로필 저장에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('프로필 설정'),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 진행 표시 바 (1/4)
              const _StepProgressBar(currentStep: 1, totalSteps: 4),
              const SizedBox(height: 6),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '1단계: 프로필 설정',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  Text(
                    '1 / 4',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              const Text(
                '프로필을 설정해주세요',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '다른 사용자에게 표시되는 정보입니다.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 40),

              // 프로필 이미지 선택 (100px)
              Center(
                child: GestureDetector(
                  onTap: (_isLoading || _isImageLoading) ? null : _pickImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2A2A2A),
                          border: Border.all(
                            color: _profileImageUrl != null
                                ? AppTheme.primaryColor
                                : const Color(0xFF2A2A2A),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: _isImageLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryColor,
                                  ),
                                )
                              : _profileImageUrl != null
                                  ? Image.network(
                                      _profileImageUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(
                                      Icons.person_rounded,
                                      size: 50,
                                      color: AppTheme.textDisabled,
                                    ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF1E1E1E), width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withOpacity(0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 36),

              // 닉네임 입력
              Row(
                children: [
                  const Text(
                    '닉네임',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _nicknameError = null;
                            });
                            _generateRandomNickname();
                          },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.casino_outlined,
                            size: 15, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          '랜덤 생성',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nicknameController,
                maxLength: 20,
                decoration: InputDecoration(
                  hintText: '2~20자 이내로 입력해주세요',
                  errorText: _nicknameError,
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 2) {
                    return '닉네임은 2자 이상 입력해주세요.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // 약관 동의
              _buildAgreementRow(
                label: '서비스 이용약관',
                checked: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v),
                url: 'https://pins.kr/terms.html',
              ),
              const SizedBox(height: 10),
              _buildAgreementRow(
                label: '개인정보 처리방침',
                checked: _agreedToPrivacy,
                onChanged: (v) => setState(() => _agreedToPrivacy = v),
                url: 'https://pins.kr/privacy.html',
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_isLoading || !_agreedToTerms || !_agreedToPrivacy) ? null : _submit,
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
                          '다음',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildAgreementRow({
    required String label,
    required bool checked,
    required void Function(bool) onChanged,
    required String url,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: AppTheme.primaryColor,
            side: const BorderSide(color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!checked),
            child: Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                const Text(' (필수)', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text(
            '보기',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.primaryColor,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// 상단 진행 표시 바
class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepProgressBar(
      {required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Row(
        children: List.generate(
          totalSteps,
          (index) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              height: 5,
              decoration: BoxDecoration(
                color: index < currentStep
                    ? AppTheme.primaryColor
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
