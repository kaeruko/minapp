import 'package:flutter/material.dart';

import 'kobo_assets.dart';
import 'kobo_models.dart';
import 'kobo_theme.dart';

class KoboHeroCard extends StatelessWidget {
  const KoboHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outerConstraints) {
        final double height = (outerConstraints.maxWidth / (898 / 404))
            .clamp(180.0, 220.0)
            .toDouble();
        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(
                KoboAssets.heroSign,
                key: const Key('kobo-hero-sign'),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KoboSpacing.lg,
                  KoboSpacing.lg,
                  KoboSpacing.lg,
                  KoboSpacing.md,
                ),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth < 360
                              ? constraints.maxWidth
                              : constraints.maxWidth * .72,
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '自分だけの小さな道具を作る',
                              style: TextStyle(
                                color: KoboColors.brown,
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: KoboSpacing.xs),
                            Text(
                              '今日、なに作る？',
                              style: KoboTextStyles.heroTitle,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class KoboPrimaryButton extends StatelessWidget {
  const KoboPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class KoboSectionHeader extends StatelessWidget {
  const KoboSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction must either both be set or both be null.',
        );

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(title, style: KoboTextStyles.sectionTitle)),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: KoboColors.navy,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: KoboSpacing.xs),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class KoboCategoryCard extends StatelessWidget {
  const KoboCategoryCard({required this.category, super.key});

  final KoboCategory category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KoboColors.paper,
        border: Border.all(color: KoboColors.divider),
        borderRadius: BorderRadius.circular(KoboRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KoboSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Image.asset(
              category.assetPath,
              key: Key('kobo-category-image-${category.title}'),
              width: 40,
              height: 40,
              cacheWidth: 120,
              cacheHeight: 120,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: KoboSpacing.xxs),
            Text(
              category.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KoboColors.ink,
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KoboAppListTile extends StatelessWidget {
  const KoboAppListTile({required this.app, super.key});

  final KoboAppSummary app;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(
        horizontal: KoboSpacing.sm,
        vertical: KoboSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: KoboColors.paper,
        border: Border.all(color: KoboColors.divider),
        borderRadius: BorderRadius.circular(KoboRadii.card),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: KoboColors.navy,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(app.icon, color: Colors.white, size: 27),
          ),
          const SizedBox(width: KoboSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  app.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KoboColors.ink,
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: KoboSpacing.xxs),
                Text(
                  app.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KoboTextStyles.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: KoboSpacing.xs),
          const Icon(Icons.chevron_right_rounded, color: KoboColors.brown),
        ],
      ),
    );
  }
}

enum KoboNavigationItem { home, create, community, profile }

class KoboBottomNavigation extends StatelessWidget {
  const KoboBottomNavigation({
    required this.selectedItem,
    required this.onSelected,
    super.key,
  });

  final KoboNavigationItem selectedItem;
  final ValueChanged<KoboNavigationItem> onSelected;

  static const List<({KoboNavigationItem item, IconData icon, String label})>
      _items = <({KoboNavigationItem item, IconData icon, String label})>[
    (item: KoboNavigationItem.home, icon: Icons.home_outlined, label: 'ホーム'),
    (
      item: KoboNavigationItem.create,
      icon: Icons.add_box_outlined,
      label: 'つくる'
    ),
    (
      item: KoboNavigationItem.community,
      icon: Icons.grid_view_outlined,
      label: 'みんなのアプリ',
    ),
    (
      item: KoboNavigationItem.profile,
      icon: Icons.person_outline,
      label: 'マイページ',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoboColors.paper,
      child: SafeArea(
        top: false,
        child: Container(
          height: 72,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: KoboColors.divider)),
          ),
          child: Row(
            children: _items.map((entry) {
              final bool selected = entry.item == selectedItem;
              return Expanded(
                child: InkWell(
                  key: Key('kobo-nav-${entry.item.name}'),
                  onTap: () => onSelected(entry.item),
                  child: Semantics(
                    selected: selected,
                    button: true,
                    label: entry.label,
                    excludeSemantics: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          entry.icon,
                          color: selected ? KoboColors.red : KoboColors.brown,
                        ),
                        const SizedBox(height: KoboSpacing.xxs),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KoboSpacing.xxs,
                          ),
                          child: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  selected ? KoboColors.red : KoboColors.brown,
                              fontSize: 11,
                              height: 1.2,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }
}
