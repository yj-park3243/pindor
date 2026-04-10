import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../providers/team_provider.dart';
import '../../repositories/team_repository.dart';
import '../../widgets/common/app_toast.dart';

/// 팀 생성 화면
class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _regionController = TextEditingController();

  String? _selectedSport;
  int _maxMembers = 10;
  bool _isLoading = false;

  static const _sports = [
    {'key': 'SOCCER', 'label': '축구', 'icon': Icons.sports_soccer},
    {'key': 'BASEBALL', 'label': '야구', 'icon': Icons.sports_baseball},
    {'key': 'BASKETBALL', 'label': '농구', 'icon': Icons.sports_basketball},
    {'key': 'LOL', 'label': 'LoL', 'icon': Icons.computer},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSport == null) {
      AppToast.warning('종목을 선택해주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      final team = await repo.createTeam({
        'name': _nameController.text.trim(),
        'sportType': _selectedSport,
        'description': _descController.text.trim(),
        'activityRegion': _regionController.text.trim(),
        'maxMembers': _maxMembers,
      });

      await ref.read(myTeamsProvider.notifier).refresh();

      if (mounted) {
        context.go('/teams/${team.id}');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('팀 생성 실패: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('팀 만들기')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ─── 종목 선택 ───
            const Text(
              '종목 선택',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: _sports.map((sport) {
                final isSelected = _selectedSport == sport['key'] as String;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedSport = sport['key'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : const Color(0xFF2A2A2A),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sport['icon'] as IconData,
                          color: isSelected ? Colors.white : AppTheme.primaryColor,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          sport['label'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isSelected ? Colors.white : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ─── 팀명 ───
            const Text(
              '팀명',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '팀 이름을 입력하세요',
              ),
              maxLength: 20,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '팀명을 입력해주세요.';
                if (v.trim().length < 2) return '최소 2자 이상 입력해주세요.';
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ─── 팀 소개 ───
            const Text(
              '팀 소개',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                hintText: '팀을 소개하는 글을 적어주세요',
              ),
              maxLines: 4,
              maxLength: 200,
            ),
            const SizedBox(height: 20),

            // ─── 활동 지역 ───
            const Text(
              '활동 지역',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _regionController,
              decoration: const InputDecoration(
                hintText: '예: 서울 강남구',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 20),

            // ─── 최대 인원 ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '최대 인원',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _maxMembers > 2
                          ? () => setState(() => _maxMembers--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$_maxMembers명',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _maxMembers < 30
                          ? () => setState(() => _maxMembers++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 36),

            // ─── 생성 버튼 ───
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('팀 만들기', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
