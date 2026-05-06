import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 종목 목록 (단일 소스)
class SportItem {
  final String value;
  final String label;
  final IconData icon;

  const SportItem(this.value, this.label, this.icon);
}

const allSports = [
  SportItem('GOLF', '골프', Icons.sports_golf_rounded),
  SportItem('BILLIARDS_4BALL', '당구 4구', Icons.sports_bar_rounded),
  SportItem('BILLIARDS_3CUSHION', '당구 3쿠션', Icons.sports_bar_rounded),
  SportItem('TENNIS', '테니스', Icons.sports_tennis_rounded),
  SportItem('TABLE_TENNIS', '탁구', Icons.sports_handball_rounded),
  SportItem('BADMINTON', '배드민턴', Icons.sports_cricket_rounded),
  SportItem('BOWLING', '볼링', Icons.sports_baseball_rounded),
  SportItem('ROCK_PAPER_SCISSORS', '가위바위보', Icons.pan_tool_rounded),
  SportItem('ARM_WRESTLING', '팔씨름', Icons.fitness_center_rounded),
];

String sportLabel(String value) {
  return allSports.firstWhere((s) => s.value == value, orElse: () => SportItem(value, value, Icons.sports)).label;
}

IconData sportIcon(String value) {
  return allSports.firstWhere((s) => s.value == value, orElse: () => SportItem(value, value, Icons.sports)).icon;
}
