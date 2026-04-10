/// 매칭 상태 조회 응답 모델
/// GET /matches/:matchId/status 응답 파싱용
/// 서버는 Match 전체 객체가 아닌 수락 상태 요약만 반환한다.
class MatchStatusResponse {
  final String matchId;
  final String status;
  final Map<String, dynamic>? myAcceptance;
  final Map<String, dynamic>? opponentAcceptance;

  const MatchStatusResponse({
    required this.matchId,
    required this.status,
    this.myAcceptance,
    this.opponentAcceptance,
  });

  factory MatchStatusResponse.fromJson(Map<String, dynamic> json) {
    return MatchStatusResponse(
      matchId: json['matchId'] as String,
      status: json['status'] as String,
      myAcceptance: json['myAcceptance'] as Map<String, dynamic>?,
      opponentAcceptance: json['opponentAcceptance'] as Map<String, dynamic>?,
    );
  }
}
