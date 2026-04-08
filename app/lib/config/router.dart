import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/profile_setup_screen.dart';
import '../screens/auth/sport_profile_setup_screen.dart';
import '../screens/auth/location_setup_screen.dart';
import '../screens/auth/pin_sport_setup_screen.dart';
import '../screens/main_tab_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/quick_match_screen.dart';
import '../screens/matching/match_list_screen.dart';
import '../screens/matching/create_match_screen.dart';
import '../screens/matching/match_request_list_screen.dart';
import '../screens/matching/match_detail_screen.dart';
import '../screens/matching/match_accept_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_room_screen.dart';
import '../screens/game/game_result_input_screen.dart';
import '../screens/game/game_confirm_screen.dart';
import '../screens/game/score_result_screen.dart';
import '../screens/ranking/map_screen.dart';
import '../screens/ranking/pin_ranking_screen.dart';
import '../screens/ranking/my_ranking_screen.dart';
import '../screens/community/pin_board_screen.dart';
import '../screens/community/post_detail_screen.dart';
import '../screens/community/create_post_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/sports_profile_screen.dart';
import '../screens/profile/notification_list_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/notification_settings_screen.dart';
import '../screens/profile/inquiry_screen.dart';
import '../screens/team/team_home_screen.dart';
import '../screens/team/create_team_screen.dart';
import '../screens/team/team_detail_screen.dart';
import '../screens/team/team_manage_screen.dart';
import '../screens/team/team_match_request_screen.dart';
import '../screens/team/team_match_list_screen.dart';
import '../screens/team/team_match_detail_screen.dart';
import '../screens/team/team_chat_screen.dart';
import '../screens/team/team_board_screen.dart';
import '../screens/team/team_post_detail_screen.dart';
import '../screens/team/team_create_post_screen.dart';
import '../screens/team/nearby_teams_screen.dart';
import '../screens/notices/notice_list_screen.dart';
import '../screens/notices/notice_detail_screen.dart';
import '../screens/disputes/create_dispute_screen.dart';
import '../screens/disputes/dispute_list_screen.dart';

/// GoRouter의 refreshListenable로 사용할 ChangeNotifier
/// authStateProvider 변경 시 GoRouter의 redirect만 재실행 (GoRouter 재생성 안 함)
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}

// ─── 라우트 경로 상수 ───
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String profileSetup = '/setup/profile';
  static const String sportProfileSetup = '/setup/sport-profile';
  static const String locationSetup = '/setup/location';
  static const String pinSportSetup = '/setup/pin-sport';

  // 메인 탭
  static const String home = '/home';
  static const String quickMatch = '/home/quick-match';
  static const String matchList = '/matches';
  static const String createMatch = '/matches/create';
  static const String matchRequests = '/matches/requests';
  static const String matchDetail = '/matches/:matchId';
  static const String matchAccept = '/matches/:matchId/accept';
  static const String chatList = '/chats';
  static const String chatRoom = '/chats/:roomId';
  static const String map = '/map';
  static const String pinRanking = '/map/ranking/:pinId';
  static const String myRanking = '/map/my-ranking';
  static const String pinBoard = '/pins/:pinId/board';
  static const String postDetail = '/pins/:pinId/posts/:postId';
  static const String createPost = '/pins/:pinId/posts/create';
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String sportsProfile = '/profile/sports';
  static const String notifications = '/profile/notifications';
  static const String settings = '/profile/settings';
  static const String notificationSettings = '/profile/settings/notifications';
  static const String inquiry = '/profile/inquiry';

  // 경기 결과
  static const String gameResultInput = '/games/:gameId/result';
  static const String gameConfirm = '/games/:gameId/confirm';
  static const String scoreResult = '/games/:gameId/score-result';

  // 공지사항
  static const String notices = '/notices';
  static const String noticeDetail = '/notices/:id';

  // 의의 제기
  static const String disputes = '/disputes';
  static const String createDispute = '/disputes/create';

  // 팀
  static const String teams = '/teams';
  static const String createTeam = '/teams/create';
  static const String nearbyTeams = '/teams/nearby';
  static const String teamDetail = '/teams/:id';
  static const String teamManage = '/teams/:id/manage';
  static const String teamMatchRequest = '/teams/:id/match/request'; // 실제 경로: /teams/:id/match/request
  static const String teamMatchList = '/teams/:id/matches';
  static const String teamMatchDetail = '/team-matches/:id';
  static const String teamChat = '/team-chats/:roomId';
  static const String teamBoard = '/teams/:id/board';
  static const String teamBoardWrite = '/teams/:id/board/write';
  static const String teamPostDetail = '/teams/:id/board/:postId';
}

/// go_router 인스턴스 프로바이더
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;
      final isLoading = authState.isLoading;
      final location = state.matchedLocation;

      // 로딩 중은 리다이렉트 없음
      if (isLoading) return null;

      // 인증 필요 없는 경로들
      final publicRoutes = [
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.profileSetup,
        AppRoutes.sportProfileSetup,
        AppRoutes.locationSetup,
        AppRoutes.pinSportSetup,
      ];

      final isPublicRoute = publicRoutes.any((r) => location.startsWith(r));

      // 비인증 사용자가 보호된 경로 접근 시
      if (!isAuthenticated && !isPublicRoute) {
        return AppRoutes.login;
      }

      // 인증된 사용자가 로그인 화면 접근 시
      if (isAuthenticated && location == AppRoutes.login) {
        return AppRoutes.home;
      }

      // 인증됐지만 초기 설정 미완료 → 설정 플로우로 강제 이동
      final isSetupRoute = location.startsWith('/setup');
      if (isAuthenticated && !isSetupRoute) {
        final user = authState.valueOrNull?.user;
        if (user != null && user.sportsProfiles.isEmpty) {
          return AppRoutes.profileSetup;
        }
      }

      return null;
    },
    routes: [
      // ─── 인증 플로우 ───
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.sportProfileSetup,
        builder: (context, state) => const SportProfileSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.locationSetup,
        builder: (context, state) => const LocationSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.pinSportSetup,
        builder: (context, state) => const PinSportSetupScreen(),
      ),

      // ─── 메인 탭 쉘 라우트 ───
      ShellRoute(
        builder: (context, state, child) => MainTabScreen(child: child),
        routes: [
          // 홈 탭
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
            routes: [
              GoRoute(
                path: 'quick-match',
                builder: (context, state) => const QuickMatchScreen(),
              ),
            ],
          ),

          // 매칭 탭
          GoRoute(
            path: AppRoutes.matchList,
            builder: (context, state) => const MatchListScreen(),
            routes: [
              GoRoute(
                path: 'requests',
                builder: (context, state) => const MatchRequestListScreen(),
              ),
              GoRoute(
                path: ':matchId',
                builder: (context, state) => MatchDetailScreen(
                  matchId: state.pathParameters['matchId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'accept',
                    builder: (context, state) => MatchAcceptScreen(
                      matchId: state.pathParameters['matchId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 채팅 탭
          GoRoute(
            path: AppRoutes.chatList,
            builder: (context, state) => const ChatListScreen(),
            routes: [
              GoRoute(
                path: ':roomId',
                builder: (context, state) => ChatRoomScreen(
                  roomId: state.pathParameters['roomId']!,
                ),
              ),
            ],
          ),

          // 랭킹/지도 탭
          GoRoute(
            path: AppRoutes.map,
            builder: (context, state) => const MapScreen(),
            routes: [
              GoRoute(
                path: 'ranking/:pinId',
                builder: (context, state) => PinRankingScreen(
                  pinId: state.pathParameters['pinId']!,
                ),
              ),
              GoRoute(
                path: 'my-ranking',
                builder: (context, state) => const MyRankingScreen(),
              ),
            ],
          ),

          // 팀 탭
          GoRoute(
            path: AppRoutes.teams,
            builder: (context, state) => const TeamHomeScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) => const CreateTeamScreen(),
              ),
              GoRoute(
                path: 'nearby',
                builder: (context, state) => const NearbyTeamsScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => TeamDetailScreen(
                  teamId: state.pathParameters['id']!,
                ),
                routes: [
                  GoRoute(
                    path: 'manage',
                    builder: (context, state) => TeamManageScreen(
                      teamId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'match/request',
                    builder: (context, state) => TeamMatchRequestScreen(
                      teamId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'matches',
                    builder: (context, state) => TeamMatchListScreen(
                      teamId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'board',
                    builder: (context, state) => TeamBoardScreen(
                      teamId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'write',
                        builder: (context, state) => TeamCreatePostScreen(
                          teamId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: ':postId',
                        builder: (context, state) => TeamPostDetailScreen(
                          teamId: state.pathParameters['id']!,
                          postId: state.pathParameters['postId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // 프로필 탭
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => const EditProfileScreen(),
              ),
              GoRoute(
                path: 'sports',
                builder: (context, state) => const SportsProfileScreen(),
              ),
              GoRoute(
                path: 'notifications',
                builder: (context, state) => const NotificationListScreen(),
              ),
            ],
          ),
        ],
      ),

      // ─── 설정 (탭 외부 — 바텀 네비 없음) ───
      GoRoute(
        path: '/profile/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationSettingsScreen(),
          ),
        ],
      ),

      // ─── 신고/문의 (탭 외부 — 바텀 네비 없음) ───
      GoRoute(
        path: '/profile/inquiry',
        builder: (context, state) => const InquiryScreen(),
      ),

      // ─── 공지사항 (탭 외부 — 바텀 네비 없음) ───
      GoRoute(
        path: '/notices',
        builder: (context, state) => const NoticeListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => NoticeDetailScreen(
              noticeId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      // ─── 매칭 생성 (탭 외부 — 바텀 네비 없음) ───
      GoRoute(
        path: AppRoutes.createMatch,
        builder: (context, state) => const CreateMatchScreen(),
      ),

      // ─── 팀 매칭 상세 (탭 외부) ───
      GoRoute(
        path: '/team-matches/:id',
        builder: (context, state) => TeamMatchDetailScreen(
          matchId: state.pathParameters['id']!,
        ),
      ),

      // ─── 팀 채팅 (탭 외부) ───
      GoRoute(
        path: '/team-chats/:roomId',
        builder: (context, state) => TeamChatScreen(
          roomId: state.pathParameters['roomId']!,
        ),
      ),

      // ─── 커뮤니티 (탭 외부) ───
      GoRoute(
        path: '/pins/:pinId/board',
        builder: (context, state) => PinBoardScreen(
          pinId: state.pathParameters['pinId']!,
        ),
        routes: [
          // 정적 경로가 동적 경로보다 먼저 정의되어야 함
          GoRoute(
            path: 'posts/create',
            builder: (context, state) => CreatePostScreen(
              pinId: state.pathParameters['pinId']!,
            ),
          ),
          GoRoute(
            path: 'posts/:postId',
            builder: (context, state) => PostDetailScreen(
              pinId: state.pathParameters['pinId']!,
              postId: state.pathParameters['postId']!,
            ),
          ),
        ],
      ),

      // ─── 게시글 상세 (독립 경로) ───
      GoRoute(
        path: '/pins/:pinId/posts/:postId',
        builder: (context, state) => PostDetailScreen(
          pinId: state.pathParameters['pinId']!,
          postId: state.pathParameters['postId']!,
        ),
      ),

      // ─── 의의 제기 (탭 외부) ───
      GoRoute(
        path: '/disputes',
        builder: (context, state) => const DisputeListScreen(),
      ),
      GoRoute(
        path: '/disputes/create',
        builder: (context, state) {
          final matchId = state.uri.queryParameters['matchId'] ?? '';
          return CreateDisputeScreen(matchId: matchId);
        },
      ),

      // ─── 경기 결과 흐름 ───
      GoRoute(
        path: '/games/:gameId/result',
        builder: (context, state) => GameResultInputScreen(
          gameId: state.pathParameters['gameId']!,
        ),
      ),
      GoRoute(
        path: '/games/:gameId/confirm',
        builder: (context, state) => GameConfirmScreen(
          gameId: state.pathParameters['gameId']!,
        ),
      ),
      GoRoute(
        path: '/games/:gameId/score-result',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ScoreResultScreen(
            gameId: state.pathParameters['gameId']!,
            previousScore: extra?['previousScore'] as int? ?? 0,
            newScore: extra?['newScore'] as int? ?? 0,
            scoreDelta: extra?['scoreDelta'] as int? ?? 0,
            isWin: extra?['isWin'] as bool? ?? false,
            previousRank: extra?['previousRank'] as int?,
            newRank: extra?['newRank'] as int?,
            isCasual: extra?['isCasual'] as bool? ?? false,
          );
        },
      ),
    ],
  );
});
