import 'package:flutter/material.dart';

import 'api.dart';

class AppVisual {
  const AppVisual({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
}

const List<AppVisual> _appVisuals = <AppVisual>[
  AppVisual(
    icon: Icons.calendar_month_rounded,
    backgroundColor: Color(0xFFDBEAFE),
    foregroundColor: Color(0xFF2563EB),
    borderColor: Color(0xFFBFDBFE),
  ),
  AppVisual(
    icon: Icons.psychology_alt_rounded,
    backgroundColor: Color(0xFFFFEDD5),
    foregroundColor: Color(0xFFF59E0B),
    borderColor: Color(0xFFFED7AA),
  ),
  AppVisual(
    icon: Icons.favorite_rounded,
    backgroundColor: Color(0xFFDCFCE7),
    foregroundColor: Color(0xFF16A34A),
    borderColor: Color(0xFFBBF7D0),
  ),
  AppVisual(
    icon: Icons.calculate_rounded,
    backgroundColor: Color(0xFFF1F5F9),
    foregroundColor: Color(0xFF64748B),
    borderColor: Color(0xFFE2E8F0),
  ),
  AppVisual(
    icon: Icons.palette_rounded,
    backgroundColor: Color(0xFFF3E8FF),
    foregroundColor: Color(0xFF9333EA),
    borderColor: Color(0xFFE9D5FF),
  ),
  AppVisual(
    icon: Icons.music_note_rounded,
    backgroundColor: Color(0xFFFCE7F3),
    foregroundColor: Color(0xFFDB2777),
    borderColor: Color(0xFFFBCFE8),
  ),
];

AppVisual appVisualFor(PublishedApp app) {
  if (app.appId.isEmpty) {
    throw ArgumentError.value(app.appId, 'app.appId', 'must not be empty');
  }
  final int hash = app.appId.runes.fold<int>(0, (int sum, int rune) => sum + rune);
  return _appVisuals[hash % _appVisuals.length];
}
