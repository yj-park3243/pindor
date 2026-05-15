import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/match.dart';

/// 진행 중 매칭(PENDING_ACCEPT / CHAT / CONFIRMED)의 socket 룸 join을
/// 앱 런타임 내내 보장하는 글로벌 매니저.
///
/// 화면별로 분산되어 있던 joinMatch/leaveMatch를 한 곳에서 관리해
/// 매칭 상세 화면을 떠나도 confirmMet/MATCH_STATUS_CHANGED 이벤트가 누락되지 않도록 한다.
class ActiveMatchRoomsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.keepAlive();
    return <String>{};
  }

  /// 매칭 목록을 받아 활성 상태 매칭 ID 집합을 socket과 동기화한다.
  void sync(List<Match> matches) {
    final activeIds = matches
        .where((m) =>
            m.status == 'PENDING_ACCEPT' ||
            m.status == 'CHAT' ||
            m.status == 'CONFIRMED')
        .map((m) => m.id)
        .toSet();

    final toJoin = activeIds.difference(state);
    final toLeave = state.difference(activeIds);

    for (final id in toJoin) {
      SocketService.instance.joinMatch(id);
    }
    for (final id in toLeave) {
      SocketService.instance.leaveMatch(id);
    }

    if (toJoin.isNotEmpty || toLeave.isNotEmpty) {
      debugPrint(
        '[ActiveMatchRooms] sync — join=${toJoin.length} leave=${toLeave.length} total=${activeIds.length}',
      );
    }

    state = activeIds;
  }

  /// 로그아웃 등 전체 초기화.
  void clear() {
    for (final id in state) {
      SocketService.instance.leaveMatch(id);
    }
    state = <String>{};
  }
}

final activeMatchRoomsProvider =
    NotifierProvider<ActiveMatchRoomsNotifier, Set<String>>(
  ActiveMatchRoomsNotifier.new,
);
