import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/team.dart';
import '../models/chat_room.dart';
import '../models/message.dart';

/// 팀 관련 API 레포지토리
class TeamRepository {
  final ApiClient _api;

  const TeamRepository(this._api);

  // ─── 팀 CRUD ───

  /// 팀 생성
  Future<Team> createTeam(Map<String, dynamic> data) async {
    final response = await _api.post('/teams', body: data);
    return Team.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 팀 상세 조회
  Future<Team> getTeam(String teamId) async {
    final response = await _api.get('/teams/$teamId');
    return Team.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 팀 정보 수정 (CAPTAIN 전용)
  Future<Team> updateTeam(String teamId, Map<String, dynamic> data) async {
    final response = await _api.patch('/teams/$teamId', body: data);
    return Team.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 팀 해산 (CAPTAIN 전용)
  Future<void> disbandTeam(String teamId) async {
    await _api.delete('/teams/$teamId');
  }

  // ─── 팀 탐색 ───

  /// 주변 팀 목록
  Future<List<Team>> getNearbyTeams({
    required double latitude,
    required double longitude,
    int radiusKm = 20,
    String? sportType,
  }) async {
    final response = await _api.get(
      '/teams/nearby',
      queryParameters: {
        'lat': latitude,
        'lng': longitude,
        'radiusKm': radiusKm,
        if (sportType != null) 'sportType': sportType,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Team.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 팀 검색
  Future<List<Team>> searchTeams({
    String? keyword,
    String? sportType,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _api.get(
      '/teams/search',
      queryParameters: {
        if (keyword != null) 'q': keyword,
        if (sportType != null) 'sportType': sportType,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Team.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 내 팀 목록
  /// NOTE: 서버에 GET /teams/my 라우트가 없음 — 서버 추가 필요
  Future<List<Team>> getMyTeams() async {
    final response = await _api.get('/teams/my');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Team.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── 멤버 관리 ───

  /// 팀 멤버 목록
  Future<List<TeamMember>> getMembers(String teamId) async {
    final response = await _api.get('/teams/$teamId/members');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 팀 가입 요청
  Future<void> joinTeam(String teamId, {String? message}) async {
    await _api.post(
      '/teams/$teamId/members/join',
      body: message != null ? {'message': message} : null,
    );
  }

  /// 멤버 추방 (CAPTAIN 전용)
  Future<void> kickMember(String teamId, String memberId) async {
    await _api.post('/teams/$teamId/members/$memberId/kick', body: {});
  }

  /// 역할 변경 (CAPTAIN 전용)
  Future<TeamMember> changeRole(
      String teamId, String memberId, String role) async {
    final response = await _api.patch(
      '/teams/$teamId/members/$memberId/role',
      body: {'role': role},
    );
    return TeamMember.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 팀 탈퇴
  Future<void> leaveTeam(String teamId) async {
    await _api.delete('/teams/$teamId/members/me');
  }

  // ─── 팀 매칭 ───

  /// 팀 매칭 요청 생성
  Future<TeamMatch> createTeamMatchRequest(
      String teamId, Map<String, dynamic> data) async {
    final response = await _api.post('/team-matches/requests', body: {
      'teamId': teamId,
      ...data,
    });
    return TeamMatch.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 팀 매칭 목록
  Future<List<TeamMatch>> getTeamMatches(
    String teamId, {
    String? status,
  }) async {
    final response = await _api.get(
      '/team-matches',
      queryParameters: {
        'teamId': teamId,
        if (status != null) 'status': status,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => TeamMatch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 팀 매칭 상세
  Future<TeamMatch> getTeamMatch(String matchId) async {
    final response = await _api.get('/team-matches/$matchId');
    return TeamMatch.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 팀 매칭 수락/확정
  Future<TeamMatch> confirmMatch(
      String matchId, Map<String, dynamic> data) async {
    final response = await _api.patch(
      '/team-matches/$matchId/confirm',
      body: data,
    );
    return TeamMatch.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 경기 결과 제출
  Future<TeamMatch> submitResult(
      String matchId, Map<String, dynamic> data) async {
    final response = await _api.post(
      '/team-matches/$matchId/result',
      body: data,
    );
    return TeamMatch.fromJson(response['data'] as Map<String, dynamic>);
  }

  // ─── 팀 채팅 ───

  /// 팀 채팅방 목록
  Future<List<ChatRoom>> getTeamChatRooms(String teamId) async {
    final response = await _api.get('/team-chat-rooms');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => ChatRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 팀 채팅 메시지 목록
  Future<List<Message>> getTeamChatMessages(
    String roomId, {
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/team-chat-rooms/$roomId/messages',
      queryParameters: {
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── 팀 게시판 ───

  /// 게시글 목록
  Future<List<TeamPost>> getTeamPosts(
    String teamId, {
    String? category,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _api.get(
      '/teams/$teamId/posts',
      queryParameters: {
        if (category != null) 'category': category,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => TeamPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 게시글 작성
  Future<TeamPost> createTeamPost(
      String teamId, Map<String, dynamic> data) async {
    final response = await _api.post('/teams/$teamId/posts', body: data);
    return TeamPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 게시글 상세
  Future<TeamPost> getTeamPost(String teamId, String postId) async {
    final response = await _api.get('/teams/$teamId/posts/$postId');
    return TeamPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 게시글 수정
  Future<TeamPost> updateTeamPost(
      String teamId, String postId, Map<String, dynamic> data) async {
    final response =
        await _api.patch('/teams/$teamId/posts/$postId', body: data);
    return TeamPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 게시글 삭제
  Future<void> deleteTeamPost(String teamId, String postId) async {
    await _api.delete('/teams/$teamId/posts/$postId');
  }

  /// 댓글 작성
  Future<TeamPostComment> createTeamPostComment(
      String teamId, String postId, Map<String, dynamic> data) async {
    final response =
        await _api.post('/teams/$teamId/posts/$postId/comments', body: data);
    return TeamPostComment.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 댓글 목록
  /// 서버에 별도 GET /teams/:id/posts/:postId/comments 라우트가 없음
  /// 대신 GET /teams/:id/posts/:postId 응답에 comments가 포함됨
  Future<List<TeamPostComment>> getTeamPostComments(
      String teamId, String postId) async {
    final response =
        await _api.get('/teams/$teamId/posts/$postId');
    final data = response['data'] as Map<String, dynamic>;
    final comments = data['comments'] as List<dynamic>? ?? [];
    return comments
        .map((e) => TeamPostComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(ApiClient.instance);
});
