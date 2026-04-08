/// 지역 핀 모델
class Pin {
  final String id;
  final String name;
  final String? slug;
  final double centerLatitude;
  final double centerLongitude;
  final String level; // DONG | GU | CITY | PROVINCE
  final String? parentPinId;
  final bool isActive;
  final int userCount;
  final int? activeMatchRequests;
  final DateTime createdAt;

  const Pin({
    required this.id,
    required this.name,
    this.slug,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.level,
    this.parentPinId,
    this.isActive = true,
    required this.userCount,
    this.activeMatchRequests,
    required this.createdAt,
  });

  factory Pin.fromJson(Map<String, dynamic> json) {
    final center = json['center'] as Map<String, dynamic>?;
    return Pin(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String?,
      centerLatitude: center != null
          ? (center['lat'] as num).toDouble()
          : (json['centerLatitude'] as num?)?.toDouble() ?? 0.0,
      centerLongitude: center != null
          ? (center['lng'] as num).toDouble()
          : (json['centerLongitude'] as num?)?.toDouble() ?? 0.0,
      level: json['level'] as String? ?? 'DONG',
      parentPinId: json['parentPinId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      userCount: json['userCount'] as int? ?? 0,
      activeMatchRequests: json['activeMatchRequests'] as int?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'center': {
          'lat': centerLatitude,
          'lng': centerLongitude,
        },
        'level': level,
        'parentPinId': parentPinId,
        'isActive': isActive,
        'userCount': userCount,
        'activeMatchRequests': activeMatchRequests,
        'createdAt': createdAt.toIso8601String(),
      };

  String get levelDisplayName {
    switch (level) {
      case 'DONG':
        return '동';
      case 'GU':
        return '구';
      case 'CITY':
        return '시';
      case 'PROVINCE':
        return '광역';
      default:
        return level;
    }
  }
}
