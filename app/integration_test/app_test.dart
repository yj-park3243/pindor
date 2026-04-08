import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spots/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('매칭 플로우', (tester) async {
    app.main();

    // pumpAndSettle 대신 pump로 고정 대기 (타이머/애니메이션 무시)
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    debugPrint('=== 1. 앱 로드 완료 ===');

    // 온보딩 넘기기
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.text('건너뛰기').evaluate().isNotEmpty) {
        await tester.tap(find.text('건너뛰기'));
        await tester.pump(const Duration(seconds: 1));
        debugPrint('=== 온보딩 건너뛰기 ===');
        break;
      }
      if (find.text('다음').evaluate().isNotEmpty) {
        await tester.tap(find.text('다음'));
        await tester.pump(const Duration(seconds: 1));
        debugPrint('=== 다음 버튼 탭 ===');
      }
      if (find.text('시작하기').evaluate().isNotEmpty) {
        await tester.tap(find.text('시작하기'));
        await tester.pump(const Duration(seconds: 1));
        debugPrint('=== 시작하기 탭 ===');
        break;
      }
    }

    // 홈 대기
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    debugPrint('=== 2. 홈 화면 대기 완료 ===');

    // 핀 탭
    final pinTab = find.text('핀');
    if (pinTab.evaluate().isNotEmpty) {
      await tester.tap(pinTab.first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      debugPrint('=== 3. 핀 탭 이동 ===');
    } else {
      debugPrint('=== 핀 탭 못 찾음 ===');
    }

    // 검색 아이콘
    final searchIcon = find.byIcon(Icons.search_rounded);
    if (searchIcon.evaluate().isNotEmpty) {
      await tester.tap(searchIcon.first);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      debugPrint('=== 4. 검색 열림 ===');

      final listTiles = find.byType(ListTile);
      if (listTiles.evaluate().isNotEmpty) {
        await tester.tap(listTiles.first);
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        debugPrint('=== 5. 핀 선택 완료 ===');
      }
    }

    // 랭크 매칭
    await tester.pump(const Duration(seconds: 1));
    final rankBtn = find.text('랭크 매칭');
    if (rankBtn.evaluate().isNotEmpty) {
      await tester.tap(rankBtn);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      debugPrint('=== 6. 매칭 생성 화면 ===');
    }

    // 매칭 요청하기
    final submitBtn = find.text('매칭 요청하기');
    if (submitBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(submitBtn);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(submitBtn);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      debugPrint('=== 7. 매칭 요청 완료 ===');
    }

    debugPrint('=== 테스트 종료 ===');
  });
}
