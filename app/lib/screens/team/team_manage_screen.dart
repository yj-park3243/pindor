import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/theme.dart';
import '../../models/team.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../repositories/team_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/team/team_member_tile.dart';

/// 팀 관리 화면 (CAPTAIN 전용)
class TeamManageScreen extends ConsumerStatefulWidget {
  final String teamId;

  const TeamManageScreen({super.key, required this.teamId});

  @override
  ConsumerState<TeamManageScreen> createState() => _TeamManageScreenState();
}

class _TeamManageScreenState extends ConsumerState<TeamManageScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _regionController = TextEditingController();
  bool _isSaving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _initControllers(Team team) {
    if (_initialized) return;
    _nameController.text = team.name;
    _descController.text = team.description ?? '';
    _regionController.text = team.activityRegion ?? '';
    _initialized = true;
  }

  Future<void> _saveInfo() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('팀명을 입력해주세요.')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.updateTeam(widget.teamId, {
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'activityRegion': _regionController.text.trim(),
      });
      ref.invalidate(teamDetailProvider(widget.teamId));

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('팀 정보가 저장되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleRecruiting(Team team) async {
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.updateTeam(widget.teamId, {
        'isRecruiting': !team.isRecruiting,
      });
      ref.invalidate(teamDetailProvider(widget.teamId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('변경 실패: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _kickMember(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('멤버 추방'),
        content: Text(
            '${member.user?.nickname ?? '멤버'}를 팀에서 추방하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('추방'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.kickMember(widget.teamId, member.id);
      ref.invalidate(teamMembersProvider(widget.teamId));

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('멤버를 추방했습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('추방 실패: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _changeRole(TeamMember member, String role) async {
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.changeRole(widget.teamId, member.id, role);
      ref.invalidate(teamMembersProvider(widget.teamId));
      // 방장 넘기기면 화면 종료
      if (role == 'CAPTAIN' && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('방장을 넘겼습니다.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('변경 실패: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _disbandTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('팀 해산'),
        content: const Text('정말 팀을 해산하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('해산'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.disbandTeam(widget.teamId);
      await ref.read(myTeamsProvider.notifier).refresh();
      if (mounted) context.go('/teams');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('해산 실패: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(teamDetailProvider(widget.teamId));
    final membersAsync = ref.watch(teamMembersProvider(widget.teamId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('팀 관리'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveInfo,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('저장'),
          ),
        ],
      ),
      body: teamAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => const ErrorView(message: '팀 정보를 불러올 수 없습니다.'),
        data: (team) {
          _initControllers(team);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ─── 팀 정보 수정 ───
              const _SectionHeader(title: '팀 정보 수정'),
              const SizedBox(height: 12),

              const Text('팀명',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: '팀 이름'),
                maxLength: 20,
              ),
              const SizedBox(height: 14),

              const Text('팀 소개',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(hintText: '팀 소개'),
                maxLines: 3,
                maxLength: 200,
              ),
              const SizedBox(height: 14),

              const Text('활동 지역',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _regionController,
                decoration: const InputDecoration(
                  hintText: '예: 서울 강남구',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // ─── 모집 상태 ───
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('멤버 모집',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('모집 중일 때 팀 탐색에 표시됩니다',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                  AdaptiveSwitch(
                    value: team.isRecruiting,
                    onChanged: (_) => _toggleRecruiting(team),
                  ),
                ],
              ),

              const Divider(height: 32),

              // ─── 멤버 관리 ───
              const _SectionHeader(title: '멤버 관리'),
              const SizedBox(height: 12),

              membersAsync.when(
                loading: () => const FullScreenLoading(),
                error: (e, _) => const ErrorView(message: '멤버 목록을 불러올 수 없습니다.'),
                data: (members) => Column(
                  children: members.map((member) {
                    final isSelf = member.userId == currentUser?.id;
                    final isMemberCaptain = member.isCaptain;

                    return TeamMemberTile(
                      member: member,
                      isSelf: isSelf,
                      showActions: !isSelf && !isMemberCaptain,
                      onTransferCaptain: isMemberCaptain
                          ? null
                          : () => _confirmAndTransferCaptain(member),
                      onToggleViceCaptain: () => _changeRole(
                        member,
                        member.isViceCaptain ? 'MEMBER' : 'VICE_CAPTAIN',
                      ),
                      onKick: () => _kickMember(member),
                    );
                  }).toList(),
                ),
              ),

              const Divider(height: 32),

              // ─── 팀 해산 ───
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _disbandTeam,
                  icon: const Icon(Icons.warning_amber_outlined,
                      color: AppTheme.errorColor),
                  label: const Text('팀 해산',
                      style: TextStyle(color: AppTheme.errorColor)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.errorColor),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndTransferCaptain(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방장 넘기기'),
        content: Text(
            '${member.user?.nickname ?? '멤버'}에게 방장을 넘기겠습니까?\n본인은 일반 팀원이 됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('넘기기'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _changeRole(member, 'CAPTAIN');
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
  }
}
