import 'package:flutter/material.dart';

import 'kobo_components.dart';
import 'kobo_models.dart';
import 'kobo_theme.dart';

class KoboHomePage extends StatelessWidget {
  const KoboHomePage({
    this.data = KoboHomeData.phaseOne,
    this.onCreate,
    this.onViewAllApps,
    this.onNavigationSelected,
    super.key,
  });

  final KoboHomeData data;
  final VoidCallback? onCreate;
  final VoidCallback? onViewAllApps;
  final ValueChanged<KoboNavigationItem>? onNavigationSelected;

  void _showNotImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$featureは次のPhaseで利用できるようになります')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('みんアプ工房')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              key: const Key('kobo-home-scroll'),
              padding: const EdgeInsets.fromLTRB(
                KoboSpacing.md,
                KoboSpacing.md,
                KoboSpacing.md,
                KoboSpacing.lg,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const KoboHeroCard(),
                      const SizedBox(height: KoboSpacing.md),
                      KoboPrimaryButton(
                        key: const Key('kobo-create-cta'),
                        label: '新しいアプリをつくる',
                        onPressed: onCreate ??
                            () => _showNotImplemented(context, 'アプリ作成機能'),
                      ),
                      const SizedBox(height: KoboSpacing.lg),
                      const KoboSectionHeader(title: 'こんなの作れます'),
                      const SizedBox(height: KoboSpacing.sm),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: KoboSpacing.sm,
                          mainAxisSpacing: KoboSpacing.sm,
                          mainAxisExtent: 96,
                        ),
                        itemCount: data.categories.length,
                        itemBuilder: (BuildContext context, int index) {
                          return KoboCategoryCard(
                            category: data.categories[index],
                          );
                        },
                      ),
                      const SizedBox(height: KoboSpacing.lg),
                      KoboSectionHeader(
                        title: '俺のアプリ',
                        actionLabel: 'すべて見る',
                        onAction: onViewAllApps ??
                            () => _showNotImplemented(context, 'アプリ一覧'),
                      ),
                      const SizedBox(height: KoboSpacing.sm),
                      ...data.apps.indexed.map(((int, KoboAppSummary) entry) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: entry.$1 == data.apps.length - 1
                                ? 0
                                : KoboSpacing.sm,
                          ),
                          child: KoboAppListTile(app: entry.$2),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: KoboBottomNavigation(
        selectedItem: KoboNavigationItem.home,
        onSelected: (KoboNavigationItem item) {
          final ValueChanged<KoboNavigationItem>? handler =
              onNavigationSelected;
          if (handler != null) {
            handler(item);
            return;
          }
          if (item == KoboNavigationItem.home) return;
          final String feature = switch (item) {
            KoboNavigationItem.home => 'ホーム',
            KoboNavigationItem.create => 'つくる',
            KoboNavigationItem.community => 'みんなのアプリ',
            KoboNavigationItem.profile => 'マイページ',
          };
          _showNotImplemented(context, feature);
        },
      ),
    );
  }
}
