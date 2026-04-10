/// 핀 게시판 게시글 모델
class PinPost {
  final String id;
  final String pinId;
  final String authorId;
  final String authorNickname;
  final String? authorProfileImageUrl;
  final String? authorTier;
  final String title;
  final String content;
  final String category; // GENERAL | MATCH_SEEK | REVIEW | NOTICE
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final List<String> imageUrls;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PinPost({
    required this.id,
    required this.pinId,
    required this.authorId,
    required this.authorNickname,
    this.authorProfileImageUrl,
    this.authorTier,
    required this.title,
    required this.content,
    required this.category,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    this.isLiked = false,
    this.imageUrls = const [],
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 서버가 images:[{imageUrl, sortOrder}] 또는 imageUrls:["url",...] 두 형태로 내려올 수 있음
  static List<String> _parseImageUrls(Map<String, dynamic> json) {
    // images 필드: PostImage 엔티티 배열 [{imageUrl: "...", sortOrder: 0}, ...]
    if (json['images'] is List) {
      return (json['images'] as List<dynamic>)
          .map((e) {
            if (e is Map<String, dynamic>) return e['imageUrl'] as String?;
            return null;
          })
          .whereType<String>()
          .toList();
    }
    // imageUrls 필드: 문자열 배열 (이전 형태 또는 클라이언트 내부 사용)
    if (json['imageUrls'] is List) {
      return (json['imageUrls'] as List<dynamic>)
          .whereType<String>()
          .toList();
    }
    return [];
  }

  factory PinPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    return PinPost(
      id: json['id'] as String,
      pinId: json['pinId'] as String? ?? '',
      authorId:
          author?['id'] as String? ?? json['authorId'] as String? ?? '',
      authorNickname: author?['nickname'] as String? ?? '',
      authorProfileImageUrl: author?['profileImageUrl'] as String?,
      authorTier: author?['tier'] as String?,
      title: json['title'] as String,
      content: json['content'] as String,
      category: json['category'] as String? ?? 'GENERAL',
      viewCount: json['viewCount'] as int? ?? 0,
      likeCount: json['likeCount'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
      imageUrls: _parseImageUrls(json),
      isDeleted: json['isDeleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(
          json['updatedAt'] as String? ?? json['createdAt'] as String),
    );
  }

  PinPost copyWith({bool? isLiked, int? likeCount, int? commentCount}) {
    return PinPost(
      id: id,
      pinId: pinId,
      authorId: authorId,
      authorNickname: authorNickname,
      authorProfileImageUrl: authorProfileImageUrl,
      authorTier: authorTier,
      title: title,
      content: content,
      category: category,
      viewCount: viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      imageUrls: imageUrls,
      isDeleted: isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String get categoryDisplayName {
    switch (category) {
      case 'GENERAL':
        return '일반';
      case 'MATCH_SEEK':
        return '상대 구함';
      case 'REVIEW':
        return '후기';
      case 'NOTICE':
        return '공지';
      default:
        return category;
    }
  }
}

/// 댓글 모델
class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String authorNickname;
  final String? authorProfileImageUrl;
  final String? authorTier;
  final String? parentId; // 대댓글인 경우
  final String content;
  final bool isDeleted;
  final List<Comment> replies;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorNickname,
    this.authorProfileImageUrl,
    this.authorTier,
    this.parentId,
    required this.content,
    this.isDeleted = false,
    this.replies = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    return Comment(
      id: json['id'] as String,
      postId: json['postId'] as String? ?? '',
      authorId:
          author?['id'] as String? ?? json['authorId'] as String? ?? '',
      authorNickname: author?['nickname'] as String? ?? '',
      authorProfileImageUrl: author?['profileImageUrl'] as String?,
      authorTier: author?['tier'] as String?,
      parentId: json['parentId'] as String?,
      content: json['content'] as String,
      isDeleted: json['isDeleted'] as bool? ?? false,
      replies: (json['replies'] as List<dynamic>?)
              ?.map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(
          json['updatedAt'] as String? ?? json['createdAt'] as String),
    );
  }

  bool get isReply => parentId != null;
}
