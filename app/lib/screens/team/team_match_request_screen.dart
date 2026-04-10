import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../repositories/team_repository.dart';
import '../../widgets/common/app_toast.dart';

/// 팀 매칭 요청 생성 화면 (CAPTAIN/VICE_CAPTAIN 전용)
class TeamMatchRequestScreen extends ConsumerStatefulWidget {
  final String teamId;

  const TeamMatchRequestScreen({super.key, required this.teamId});

  @override
  ConsumerState<TeamMatchRequestScreen> createState() =>
      _TeamMatchRequestScreenState();
}

class _TeamMatchRequestScreenState
    extends ConsumerState<TeamMatchRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _venueController = TextEditingController();

  DateTime? _selectedDate;
  String? _selectedTimeSlot;
  int _radiusKm = 10;
  bool _isLoading = false;
  bool _hasPermission = true;

  static const _timeSlots = [
    ('MORNING', '오전 (06:00~12:00)'),
    ('AFTERNOON', '오후 (12:00~18:00)'),
    ('EVENING', '저녁 (18:00~22:00)'),
    ('ANY', '미정'),
  ];

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final currentUser = ref.read(currentUserProvider);
    final membersAsync = ref.read(teamMembersProvider(widget.teamId));
    final members = membersAsync.valueOrNull;
    if (members != null && currentUser != null) {
      final myMember = members.where((m) => m.userId == currentUser.id);
      if (myMember.isEmpty || !myMember.first.isLeader) {
        setState(() => _hasPermission = false);
        if (mounted) {
          AppToast.warning('방장 또는 부방장만 매칭 요청을 보낼 수 있습니다.');
          context.pop();
        }
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      AppToast.warning('날짜를 선택해주세요.');
      return;
    }
    if (_selectedTimeSlot == null) {
      AppToast.warning('시간대를 선택해주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.createTeamMatchRequest(widget.teamId, {
        'scheduledDate': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'timeSlot': _selectedTimeSlot,
        'venueName': _venueController.text.trim(),
        'radiusKm': _radiusKm,
        'message': _messageController.text.trim(),
      });

      ref.invalidate(teamMatchesProvider(widget.teamId));

      if (mounted) {
        AppToast.success('팀 매칭 요청을 보냈습니다!');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('요청 실패: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('팀 매칭 요청')),
        body: const Center(
          child: Text(
            '방장 또는 부방장만 매칭 요청을 보낼 수 있습니다.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('팀 매칭 요청')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ─── 날짜 선택 ───
            const _SectionLabel(text: '경기 날짜'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        color: AppTheme.textSecondary, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      _selectedDate != null
                          ? DateFormat('yyyy년 MM월 dd일 (EEE)', 'ko').format(_selectedDate!)
                          : '날짜를 선택하세요',
                      style: TextStyle(
                        color: _selectedDate != null
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ─── 시간대 선택 ───
            const _SectionLabel(text: '시간대'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _timeSlots.map((slot) {
                final isSelected = _selectedTimeSlot == slot.$1;
                return ChoiceChip(
                  label: Text(slot.$2),
                  selected: isSelected,
                  onSelected: (_) =>
                      setState(() => _selectedTimeSlot = slot.$1),
                  selectedColor: AppTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ─── 장소 ───
            const _SectionLabel(text: '경기 장소 (선택)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _venueController,
              decoration: const InputDecoration(
                hintText: '예: 서울숲 풋살파크',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 20),

            // ─── 반경 ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionLabel(text: '상대팀 탐색 반경'),
                Text(
                  '$_radiusKm km',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            Slider(
              value: _radiusKm.toDouble(),
              min: 5,
              max: 50,
              divisions: 9,
              label: '$_radiusKm km',
              onChanged: (v) => setState(() => _radiusKm = v.round()),
              activeColor: AppTheme.primaryColor,
            ),
            const SizedBox(height: 20),

            // ─── 메시지 ───
            const _SectionLabel(text: '메시지 (선택)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: '상대 팀에게 전달할 메시지를 입력하세요',
              ),
              maxLines: 3,
              maxLength: 200,
            ),
            const SizedBox(height: 32),

            // ─── 요청 버튼 ───
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('매칭 요청 보내기',
                        style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }
}
