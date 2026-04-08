import 'user.dart';

/// 팀 모델
class Team {
  final String id;
  final String name;
  final String slug;
  final String sportType;
  final String? logoUrl;
  final String? description;
  final String? activityRegion;
  final int currentMembers;
  final int maxMembers;
  final int wins;
  final int losses;
  final int draws;
  final int teamScore;
  final bool isRecruiting;
  final String status; // ACTIVE | DISBANDED
  final DateTime createdAt;

  const Team({
    required this.id,
    required this.name,
    required this.slug,
    required this.sportType,
    this.logoUrl,
    this.description,
    this.activityRegion,
    required this.currentMembers,
    required this.maxMembers,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.teamScore,
    required this.isRecruiting,
    required this.status,
    required this.createdAt,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      sportType: json['sportType'] as String,
      logoUrl: json['logoUrl'] as String?,
      description: json['description'] as String?,
      activityRegion: json['activityRegion'] as String?,
      currentMembers: json['currentMembers'] as int? ?? 0,
      maxMembers: json['maxMembers'] as int? ?? 10,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      draws: json['draws'] as int? ?? 0,
      teamScore: json['teamScore'] as int? ?? 1000,
      isRecruiting: json['isRecruiting'] as bool? ?? true,
      status: json['status'] as String? ?? 'ACTIVE',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'sportType': sportType,
        'logoUrl': logoUrl,
        'description': description,
        'activityRegion': activityRegion,
        'currentMembers': currentMembers,
        'maxMembers': maxMembers,
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'teamScore': teamScore,
        'isRecruiting': isRecruiting,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
      };

  Team copyWith({
    String? name,
    String? logoUrl,
    String? description,
    String? activityRegion,
    int? maxMembers,
    bool? isRecruiting,
    String? status,
  }) {
    return Team(
      id: id,
      name: name ?? this.name,
      slug: slug,
      sportType: sportType,
      logoUrl: logoUrl ?? this.logoUrl,
      description: description ?? this.description,
      activityRegion: activityRegion ?? this.activityRegion,
      currentMembers: currentMembers,
      maxMembers: maxMembers ?? this.maxMembers,
      wins: wins,
      losses: losses,
      draws: draws,
      teamScore: teamScore,
      isRecruiting: isRecruiting ?? this.isRecruiting,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  /// 종목 한글명
  String get sportTypeDisplayName {
    switch (sportType.toUpperCase()) {
      case 'SOCCER':
        return '축구';
      case 'BASEBALL':
        return '야구';
      case 'BASKETBALL':
        return '농구';
      case 'LOL':
        return 'LoL';
      case 'GOLF':
        return '골프';
      default:
        return sportType;
    }
  }

  bool get isActive => status == 'ACTIVE';
}

/// 팀 멤버 모델
class TeamMember {
  final String id;
  final String teamId;
  final String userId;
  final String role; // CAPTAIN | VICE_CAPTAIN | MEMBER
  final String? position;
  final String status; // ACTIVE | PENDING | KICKED
  final DateTime joinedAt;
  final User? user;

  const TeamMember({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.role,
    this.position,
    required this.status,
    required this.joinedAt,
    this.user,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] as String,
      teamId: json['teamId'] as String,
      userId: json['userId'] as String,
      role: json['role'] as String? ?? 'MEMBER',
      position: json['position'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      user: json['user'] != null
          ? User.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isCaptain => role == 'CAPTAIN';
  bool get isViceCaptain => role == 'VICE_CAPTAIN';
  bool get isLeader => isCaptain || isViceCaptain;

  String get roleDisplayName {
    switch (role) {
      case 'CAPTAIN':
        return '방장';
      case 'VICE_CAPTAIN':
        return '부방장';
      default:
        return '팀원';
    }
  }
}

/// 팀 매칭 모델
class TeamMatch {
  final String id;
  final String homeTeamId;
  final String awayTeamId;
  final String sportType;
  final String status; // PENDING | ACCEPTED | CONFIRMED | COMPLETED | CANCELLED
  final int? homeScore;
  final int? awayScore;
  final String? winnerTeamId;
  final String resultStatus; // PENDING | HOME_WIN | AWAY_WIN | DRAW
  final Team? homeTeam;
  final Team? awayTeam;
  final String? scheduledDate;
  final String? scheduledTime;
  final String? venueName;
  final String? message;
  final String? chatRoomId;
  final DateTime createdAt;

  const TeamMatch({
    required this.id,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.sportType,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.winnerTeamId,
    required this.resultStatus,
    this.homeTeam,
    this.awayTeam,
    this.scheduledDate,
    this.scheduledTime,
    this.venueName,
    this.message,
    this.chatRoomId,
    required this.createdAt,
  });

  factory TeamMatch.fromJson(Map<String, dynamic> json) {
    return TeamMatch(
      id: json['id'] as String,
      homeTeamId: json['homeTeamId'] as String,
      awayTeamId: json['awayTeamId'] as String,
      sportType: json['sportType'] as String,
      status: json['status'] as String? ?? 'PENDING',
      homeScore: json['homeScore'] as int?,
      awayScore: json['awayScore'] as int?,
      winnerTeamId: json['winnerTeamId'] as String?,
      resultStatus: json['resultStatus'] as String? ?? 'PENDING',
      homeTeam: json['homeTeam'] != null
          ? Team.fromJson(json['homeTeam'] as Map<String, dynamic>)
          : null,
      awayTeam: json['awayTeam'] != null
          ? Team.fromJson(json['awayTeam'] as Map<String, dynamic>)
          : null,
      scheduledDate: json['scheduledDate'] as String?,
      scheduledTime: json['scheduledTime'] as String?,
      venueName: json['venueName'] as String?,
      message: json['message'] as String?,
      chatRoomId: json['chatRoomId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isAccepted => status == 'ACCEPTED';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';

  String get statusDisplayName {
    switch (status) {
      case 'PENDING':
        return '요청 중';
      case 'ACCEPTED':
        return '수락됨';
      case 'CONFIRMED':
        return '경기 확정';
      case 'COMPLETED':
        return '경기 완료';
      case 'CANCELLED':
        return '취소됨';
      default:
        return status;
    }
  }
}

/// 팀 게시글 모델
class TeamPost {
  final String id;
  final String teamId;
  final String authorId;
  final String category; // NOTICE | SCHEDULE | FREE
  final String title;
  final String content;
  final bool isPinned;
  final int viewCount;
  final DateTime createdAt;
  final User? author;
  final int commentCount;

  const TeamPost({
    required this.id,
    required this.teamId,
    required this.authorId,
    required this.category,
    required this.title,
    required this.content,
    required this.isPinned,
    required this.viewCount,
    required this.createdAt,
    this.author,
    this.commentCount = 0,
  });

  factory TeamPost.fromJson(Map<String, dynamic> json) {
    return TeamPost(
      id: json['id'] as String,
      teamId: json['teamId'] as String,
      authorId: json['authorId'] as String,
      category: json['category'] as String? ?? 'FREE',
      title: json['title'] as String,
      content: json['content'] as String,
      isPinned: json['isPinned'] as bool? ?? false,
      viewCount: json['viewCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      author: json['author'] != null
          ? User.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      commentCount: json['commentCount'] as int? ?? 0,
    );
  }

  String get categoryDisplayName {
    switch (category) {
      case 'NOTICE':
        return '공지';
      case 'SCHEDULE':
        return '일정';
      default:
        return '자유';
    }
  }
}

/// 팀 게시글 댓글 모델
class TeamPostComment {
  final String id;
  final String postId;
  final String authorId;
  final String? parentId;
  final String content;
  final DateTime createdAt;
  final User? author;
  final List<TeamPostComment> replies;

  const TeamPostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.parentId,
    required this.content,
    required this.createdAt,
    this.author,
    this.replies = const [],
  });

  factory TeamPostComment.fromJson(Map<String, dynamic> json) {
    return TeamPostComment(
      id: json['id'] as String,
      postId: json['postId'] as String,
      authorId: json['authorId'] as String,
      parentId: json['parentId'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      author: json['author'] != null
          ? User.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      replies: (json['replies'] as List<dynamic>?)
              ?.map((e) =>
                  TeamPostComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
