import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notice.dart';
import '../repositories/notice_repository.dart';

// TTL: 고정 공지 목록을 1시간마다 재조회
const _pinnedNoticesTtl = Duration(hours: 1);

/// 상단 고정 공지 프로바이더 — keepAlive + 1시간 TTL 자동 갱신
///
/// - keepAlive로 앱이 살아있는 동안 메모리에 유지
/// - 조회 성공 후 1시간 뒤 자동으로 invalidate → 재조회
/// - 화면이 없어도 백그라운드 유지 가능
final pinnedNoticesProvider = FutureProvider<List<Notice>>((ref) async {
  final link = ref.keepAlive();

  // 조회 완료 후 TTL 타이머 설정: 만료 시 캐시 해제 → 다음 접근 시 재조회
  Timer? ttlTimer;
  ref.onDispose(() => ttlTimer?.cancel());

  final notices =
      await ref.read(noticeRepositoryProvider).getPinnedNotices();

  ttlTimer = Timer(_pinnedNoticesTtl, () {
    debugPrint('[NoticeProvider] 고정 공지 TTL 만료 — 캐시 해제');
    link.close(); // keepAlive 해제: 다음 구독 시 서버 재조회
  });

  return notices;
});

final noticeListProvider = FutureProvider.autoDispose<List<Notice>>((ref) async {
  return ref.read(noticeRepositoryProvider).getNotices();
});

final noticeDetailProvider =
    FutureProvider.autoDispose.family<Notice, String>((ref, id) async {
  return ref.read(noticeRepositoryProvider).getNotice(id);
});
