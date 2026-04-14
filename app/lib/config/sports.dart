import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 앱 전체에서 사용하는 종목 목록 (단일 소스)
class SportItem {
  final String value;
  final String label;
  final IconData icon;

  const SportItem(this.value, this.label, this.icon);
}

const allSports = [
  SportItem('GOLF', '골프', Symbols.sports_golf_rounded),
  SportItem('BILLIARDS_4BALL', '당구 4구', Symbols.sports_bar_rounded),
  SportItem('BILLIARDS_3CUSHION', '당구 3쿠션', Symbols.sports_bar_rounded),
  SportItem('TENNIS', '테니스', Symbols.sports_tennis_rounded),
  SportItem('TABLE_TENNIS', '탁구', Symbols.badminton_rounded),
  SportItem('BADMINTON', '배드민턴', Symbols.sports_cricket_rounded),
  SportItem('BOWLING', '볼링', Symbols.sports_baseball_rounded),
  SportItem('ROCK_PAPER_SCISSORS', '가위바위보', Icons.pan_tool_rounded),
  SportItem('ARM_WRESTLING', '팔씨름', Symbols.fitness_center_rounded),
];

String sportLabel(String value) {
  return allSports.firstWhere((s) => s.value == value, orElse: () => SportItem(value, value, Icons.sports)).label;
}

IconData sportIcon(String value) {
  return allSports.firstWhere((s) => s.value == value, orElse: () => SportItem(value, value, Icons.sports)).icon;
}
