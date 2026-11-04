import 'package:flutter/material.dart';

@immutable
class KoboCategory {
  const KoboCategory({required this.title, required this.icon});

  final String title;
  final IconData icon;
}

@immutable
class KoboAppSummary {
  const KoboAppSummary({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

@immutable
class KoboHomeData {
  const KoboHomeData({required this.categories, required this.apps});

  final List<KoboCategory> categories;
  final List<KoboAppSummary> apps;

  static const KoboHomeData phaseOne = KoboHomeData(
    categories: <KoboCategory>[
      KoboCategory(title: '晩酌予算', icon: Icons.savings_outlined),
      KoboCategory(title: '町中華メモ', icon: Icons.restaurant_outlined),
      KoboCategory(title: '昼メシルーレット', icon: Icons.casino_outlined),
      KoboCategory(title: '小遣い管理', icon: Icons.account_balance_wallet_outlined),
    ],
    apps: <KoboAppSummary>[
      KoboAppSummary(
        title: 'せんべろ計算機',
        description: '今月あと何回飲みに行ける？',
        icon: Icons.calculate_outlined,
      ),
      KoboAppSummary(
        title: '町中華メモ',
        description: 'また行きたい店を記録',
        icon: Icons.edit_note_outlined,
      ),
    ],
  );
}
