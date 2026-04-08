import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notice.dart';
import '../repositories/notice_repository.dart';

final pinnedNoticesProvider = FutureProvider.autoDispose<List<Notice>>((ref) async {
  return ref.read(noticeRepositoryProvider).getPinnedNotices();
});

final noticeListProvider = FutureProvider.autoDispose<List<Notice>>((ref) async {
  return ref.read(noticeRepositoryProvider).getNotices();
});

final noticeDetailProvider =
    FutureProvider.autoDispose.family<Notice, String>((ref, id) async {
  return ref.read(noticeRepositoryProvider).getNotice(id);
});
