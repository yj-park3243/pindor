import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team.dart';
import '../models/chat_room.dart';
import '../repositories/team_repository.dart';

// ─── 내 팀 목록 ───

class MyTeamsNotifier extends AutoDisposeNotifier<AsyncValue<List<Team>>> {
  @override
  AsyncValue<List<Team>> build() {
    Future.microtask(() => _load());
    return const AsyncLoading();
  }

  Future<void> _load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(teamRepositoryProvider).getMyTeams();
    });
  }

  Future<void> refresh() => _load();
}

final myTeamsProvider =
    AutoDisposeNotifierProvider<MyTeamsNotifier, AsyncValue<List<Team>>>(
  MyTeamsNotifier.new,
);

// ─── 팀 상세 ───

final teamDetailProvider =
    FutureProvider.autoDispose.family<Team, String>((ref, teamId) async {
  final repo = ref.read(teamRepositoryProvider);
  return repo.getTeam(teamId);
});

// ─── 팀 멤버 목록 ───

final teamMembersProvider =
    FutureProvider.autoDispose.family<List<TeamMember>, String>(
  (ref, teamId) async {
    final repo = ref.read(teamRepositoryProvider);
    return repo.getMembers(teamId);
  },
);

// ─── 팀 매칭 목록 ───

class TeamMatchesState {
  final List<TeamMatch> active;
  final List<TeamMatch> completed;
  final bool isLoading;
  final String? error;

  const TeamMatchesState({
    this.active = const [],
    this.completed = const [],
    this.isLoading = false,
    this.error,
  });

  TeamMatchesState copyWith({
    List<TeamMatch>? active,
    List<TeamMatch>? completed,
    bool? isLoading,
    String? error,
  }) {
    return TeamMatchesState(
      active: active ?? this.active,
      completed: completed ?? this.completed,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TeamMatchesNotifier
    extends AutoDisposeFamilyNotifier<TeamMatchesState, String> {
  late String _teamId;

  @override
  TeamMatchesState build(String teamId) {
    _teamId = teamId;
    Future.microtask(() => _load());
    return const TeamMatchesState(isLoading: true);
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      final results = await Future.wait([
        repo.getTeamMatches(_teamId, status: 'ACTIVE'),
        repo.getTeamMatches(_teamId, status: 'COMPLETED'),
      ]);
      state = state.copyWith(
        active: results[0],
        completed: results[1],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => _load();
}

final teamMatchesProvider = NotifierProvider.autoDispose
    .family<TeamMatchesNotifier, TeamMatchesState, String>(
  TeamMatchesNotifier.new,
);

// ─── 팀 매칭 상세 ───

final teamMatchDetailProvider =
    FutureProvider.autoDispose.family<TeamMatch, String>((ref, matchId) async {
  final repo = ref.read(teamRepositoryProvider);
  return repo.getTeamMatch(matchId);
});

// ─── 팀 게시글 목록 ───

class TeamPostsState {
  final List<TeamPost> all;
  final List<TeamPost> notice;
  final List<TeamPost> schedule;
  final List<TeamPost> free;
  final bool isLoading;
  final String? error;

  const TeamPostsState({
    this.all = const [],
    this.notice = const [],
    this.schedule = const [],
    this.free = const [],
    this.isLoading = false,
    this.error,
  });

  TeamPostsState copyWith({
    List<TeamPost>? all,
    List<TeamPost>? notice,
    List<TeamPost>? schedule,
    List<TeamPost>? free,
    bool? isLoading,
    String? error,
  }) {
    return TeamPostsState(
      all: all ?? this.all,
      notice: notice ?? this.notice,
      schedule: schedule ?? this.schedule,
      free: free ?? this.free,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TeamPostsNotifier
    extends AutoDisposeFamilyNotifier<TeamPostsState, String> {
  late String _teamId;

  @override
  TeamPostsState build(String teamId) {
    _teamId = teamId;
    Future.microtask(() => _load());
    return const TeamPostsState(isLoading: true);
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      final results = await Future.wait([
        repo.getTeamPosts(_teamId),
        repo.getTeamPosts(_teamId, category: 'NOTICE'),
        repo.getTeamPosts(_teamId, category: 'SCHEDULE'),
        repo.getTeamPosts(_teamId, category: 'FREE'),
      ]);
      state = state.copyWith(
        all: results[0],
        notice: results[1],
        schedule: results[2],
        free: results[3],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => _load();

  Future<TeamPost> createPost(Map<String, dynamic> data) async {
    final repo = ref.read(teamRepositoryProvider);
    final post = await repo.createTeamPost(_teamId, data);
    await _load();
    return post;
  }

  Future<void> deletePost(String postId) async {
    final repo = ref.read(teamRepositoryProvider);
    await repo.deleteTeamPost(_teamId, postId);
    await _load();
  }
}

final teamPostsProvider = NotifierProvider.autoDispose
    .family<TeamPostsNotifier, TeamPostsState, String>(
  TeamPostsNotifier.new,
);

// ─── 팀 게시글 상세 ───

final teamPostDetailProvider =
    FutureProvider.autoDispose.family<TeamPost, ({String teamId, String postId})>(
  (ref, args) async {
    final repo = ref.read(teamRepositoryProvider);
    return repo.getTeamPost(args.teamId, args.postId);
  },
);

// ─── 팀 게시글 댓글 ───

final teamPostCommentsProvider = FutureProvider.autoDispose
    .family<List<TeamPostComment>, ({String teamId, String postId})>(
  (ref, args) async {
    final repo = ref.read(teamRepositoryProvider);
    return repo.getTeamPostComments(args.teamId, args.postId);
  },
);

// ─── 주변 팀 ───

class NearbyTeamsState {
  final List<Team> teams;
  final bool isLoading;
  final String? error;
  final String? selectedSportType;

  const NearbyTeamsState({
    this.teams = const [],
    this.isLoading = false,
    this.error,
    this.selectedSportType,
  });

  NearbyTeamsState copyWith({
    List<Team>? teams,
    bool? isLoading,
    String? error,
    String? selectedSportType,
    bool clearSportType = false,
  }) {
    return NearbyTeamsState(
      teams: teams ?? this.teams,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedSportType:
          clearSportType ? null : (selectedSportType ?? this.selectedSportType),
    );
  }
}

class NearbyTeamsNotifier extends AutoDisposeNotifier<NearbyTeamsState> {
  double? _lat;
  double? _lng;

  @override
  NearbyTeamsState build() {
    return const NearbyTeamsState();
  }

  Future<void> load({
    required double latitude,
    required double longitude,
    String? sportType,
  }) async {
    _lat = latitude;
    _lng = longitude;
    state = state.copyWith(isLoading: true, selectedSportType: sportType);
    try {
      final repo = ref.read(teamRepositoryProvider);
      final teams = await repo.getNearbyTeams(
        latitude: latitude,
        longitude: longitude,
        sportType: sportType,
      );
      state = NearbyTeamsState(
        teams: teams,
        isLoading: false,
        selectedSportType: sportType,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> filterBySport(String? sportType) async {
    if (_lat == null || _lng == null) return;
    await load(latitude: _lat!, longitude: _lng!, sportType: sportType);
  }
}

final nearbyTeamsProvider =
    AutoDisposeNotifierProvider<NearbyTeamsNotifier, NearbyTeamsState>(
  NearbyTeamsNotifier.new,
);

// ─── 팀 채팅방 목록 ───

final teamChatRoomsProvider =
    FutureProvider.autoDispose.family<List<ChatRoom>, String>(
  (ref, teamId) async {
    final repo = ref.read(teamRepositoryProvider);
    return repo.getTeamChatRooms(teamId);
  },
);
