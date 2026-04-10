import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 종목 목록 (단일 소스)
class SportItem {
  final String value;
  final String label;
  final IconData icon;

  const SportItem(this.value, this.label, this.icon);
}

const allSports = [
  SportItem('GOLF', '골프', Icons.sports_golf),
  SportItem('BILLIARDS', '당구', Icons.circle_outlined),
  SportItem('TENNIS', '테니스', Icons.sports_tennis),
  SportItem('TABLE_TENNIS', '탁구', Icons.sports_tennis),
  SportItem('BADMINTON', '배드민턴', Icons.sports_tennis),
  SportItem('BOWLING', '볼링', Icons.sports),
  SportItem('ROCK_PAPER_SCISSORS', '가위바위보', Icons.pan_tool_rounded),
  SportItem('ARM_WRESTLING', '팔씨름', Icons.fitness_center),
];

String sportLabel(String value) {
  return allSports.firstWhere((s) => s.value == value, orElse: () => SportItem(value, value, Icons.sports)).label;
}

IconData sportIcon(String value) {
  return allSports.firstWhere((s) => s.value == value, orElse: () => SportItem(value, value, Icons.sports)).icon;
}
