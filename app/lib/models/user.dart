import 'sports_profile.dart';

/// 사용자 모델
class User {
  final String id;
  final String? email;
  final String nickname;
  final String? profileImageUrl;
  final String? phone;
  final String status; // ACTIVE | SUSPENDED | WITHDRAWN
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final List<SportsProfile> sportsProfiles;
  final UserLocation? location;
  final String? gender; // MALE | FEMALE | OTHER
  final DateTime? birthDate;

  const User({
    required this.id,
    this.email,
    required this.nickname,
    this.profileImageUrl,
    this.phone,
    required this.status,
    required this.createdAt,
    this.lastLoginAt,
    this.sportsProfiles = const [],
    this.location,
    this.gender,
    this.birthDate,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String?,
      nickname: json['nickname'] as String,
      profileImageUrl: json['profileImageUrl'] as String?,
      phone: json['phone'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.parse(json['lastLoginAt'] as String)
          : null,
      sportsProfiles: (json['sportsProfiles'] as List<dynamic>?)
              ?.map((e) => SportsProfile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      location: json['location'] != null
          ? UserLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      gender: json['gender'] as String?,
      birthDate: json['birthDate'] != null
          ? DateTime.parse(json['birthDate'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'nickname': nickname,
        'profileImageUrl': profileImageUrl,
        'phone': phone,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'sportsProfiles': sportsProfiles.map((e) => e.toJson()).toList(),
        'location': location?.toJson(),
        'gender': gender,
        'birthDate': birthDate?.toIso8601String(),
      };

  User copyWith({
    String? nickname,
    String? profileImageUrl,
    String? phone,
    String? status,
    List<SportsProfile>? sportsProfiles,
    UserLocation? location,
    String? gender,
    DateTime? birthDate,
  }) {
    return User(
      id: id,
      email: email,
      nickname: nickname ?? this.nickname,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      sportsProfiles: sportsProfiles ?? this.sportsProfiles,
      location: location ?? this.location,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
    );
  }

  bool get isActive => status == 'ACTIVE';

  /// birthDate 기반 만 나이 계산
  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    int age = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      age -= 1;
    }
    return age;
  }

  /// 주 스포츠 프로필 (첫 번째)
  SportsProfile? get primarySportsProfile =>
      sportsProfiles.isNotEmpty ? sportsProfiles.first : null;
}

/// 사용자 위치 정보
class UserLocation {
  final double latitude;
  final double longitude;
  final String? homeAddress;
  final int matchRadiusKm;

  const UserLocation({
    required this.latitude,
    required this.longitude,
    this.homeAddress,
    required this.matchRadiusKm,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      homeAddress: json['homeAddress'] as String?,
      matchRadiusKm: json['matchRadiusKm'] as int? ?? 10,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'homeAddress': homeAddress,
        'matchRadiusKm': matchRadiusKm,
      };
}

/// 타 사용자 공개 프로필
class UserProfile {
  final String id;
  final String nickname;
  final String? profileImageUrl;
  final String tier;
  final int currentScore;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final String sportType;

  const UserProfile({
    required this.id,
    required this.nickname,
    this.profileImageUrl,
    required this.tier,
    required this.currentScore,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.sportType,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      profileImageUrl: json['profileImageUrl'] as String?,
      tier: json['tier'] as String? ?? 'BRONZE',
      currentScore: json['currentScore'] as int? ?? 1000,
      gamesPlayed: json['gamesPlayed'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      sportType: json['sportType'] as String? ?? 'GOLF',
    );
  }

  double get winRate =>
      gamesPlayed > 0 ? (wins / gamesPlayed * 100) : 0.0;
}
