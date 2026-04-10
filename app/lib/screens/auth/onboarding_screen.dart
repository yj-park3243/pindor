import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../config/theme.dart';

/// 온보딩 화면 (3페이지 소개)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.location_on_rounded,
      illustrationIcon: Icons.map_rounded,
      title: '내 근처에서\n대결 상대를 찾아보세요',
      subtitle: '위치 기반으로 가까운 곳의 스포츠\n대결 상대를 빠르게 매칭해드립니다.',
      iconColor: AppTheme.primaryColor,
      bgColor: Color(0xFF2A1A0E),
    ),
    _OnboardingPageData(
      icon: Icons.people_rounded,
      illustrationIcon: Icons.sports_kabaddi_rounded,
      title: '실력에 맞는 상대와\n1:1 매칭',
      subtitle: 'ELO 점수 기반으로 나와 비슷한\n실력의 상대를 공정하게 연결합니다.',
      iconColor: Color(0xFFE91E63),
      bgColor: Color(0xFF2A0D17),
    ),
    _OnboardingPageData(
      icon: Icons.emoji_events_rounded,
      illustrationIcon: Icons.leaderboard_rounded,
      title: '승리하고\n랭킹을 올려보세요',
      subtitle: '지역 핀 랭킹에서 실력을 증명하고\n브론즈에서 플래티넘까지 도전하세요.',
      iconColor: AppTheme.goldColor,
      bgColor: Color(0xFF2A2208),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToLogin() {
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // 건너뛰기 버튼 (우상단)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 핀돌 로고 텍스트 (작게)
                  const Text(
                    '핀돌',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryColor,
                      letterSpacing: 1,
                    ),
                  ),
                  TextButton(
                    onPressed: _goToLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                    ),
                    child: const Text(
                      '건너뛰기',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

            // 페이지 뷰 (상단 60%)
            Expanded(
              flex: 6,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _OnboardingPage(data: _pages[index]);
                },
              ),
            ),

            // 하단 영역 (40%): 인디케이터 + 버튼
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                children: [
                  // 커스텀 도트 인디케이터
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => _DotIndicator(
                        isActive: _currentPage == index,
                        color: _pages[index].iconColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 액션 버튼 (마지막 페이지: 시작하기, 나머지: 다음)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: SizedBox(
                      key: ValueKey(isLastPage),
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!isLastPage) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _goToLogin();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pages[_currentPage].iconColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isLastPage ? '시작하기' : '다음',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 커스텀 도트 인디케이터
class _DotIndicator extends StatelessWidget {
  final bool isActive;
  final Color color;

  const _DotIndicator({required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 28 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? color : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final IconData illustrationIcon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color bgColor;

  const _OnboardingPageData({
    required this.icon,
    required this.illustrationIcon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.bgColor,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 상단 일러스트 영역 (배경 원형 + 아이콘)
          Stack(
            alignment: Alignment.center,
            children: [
              // 외부 큰 원
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: data.bgColor.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
              ),
              // 내부 중간 원
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: data.bgColor,
                  shape: BoxShape.circle,
                ),
              ),
              // 메인 아이콘
              Icon(
                data.icon,
                size: 80,
                color: data.iconColor,
              ),
              // 우하단 서브 아이콘
              Positioned(
                bottom: 20,
                right: 20,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: data.iconColor.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    data.illustrationIcon,
                    size: 24,
                    color: data.iconColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // 제목 (20pt bold)
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.35,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 16),

          // 설명 (14pt, 2줄)
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}
