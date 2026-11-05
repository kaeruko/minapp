import 'package:flutter/material.dart';

import '../hosted_app_management_api.dart';

import 'kobo_components.dart';
import 'kobo_models.dart';
import 'kobo_theme.dart';

class KoboHomePage extends StatelessWidget {
  const KoboHomePage({
    this.data = KoboHomeData.phaseOne,
    this.onCreate,
    this.onViewAllApps,
    this.onCategorySelected,
    this.onNavigationSelected,
    this.signedIn = false,
    this.apps = const <ManagedHostedApp>[],
    this.appsLoading = false,
    this.appsError,
    this.onAppSelected,
    this.onRetryApps,
    super.key,
  });

  final KoboHomeData data;
  final VoidCallback? onCreate;
  final VoidCallback? onViewAllApps;
  final ValueChanged<KoboCategory>? onCategorySelected;
  final ValueChanged<KoboNavigationItem>? onNavigationSelected;
  final bool signedIn;
  final List<ManagedHostedApp> apps;
  final bool appsLoading;
  final String? appsError;
  final ValueChanged<ManagedHostedApp>? onAppSelected;
  final VoidCallback? onRetryApps;

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
                            onTap: () {
                              final ValueChanged<KoboCategory>? handler =
                                  onCategorySelected;
                              if (handler != null) {
                                handler(data.categories[index]);
                              } else {
                                _showNotImplemented(context, '作品の検索');
                              }
                            },
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
                      if (!signedIn)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: KoboSpacing.md,
                          ),
                          child: Text(
                            'ログインすると、自分で作ったアプリをここに表示できます。',
                            style: KoboTextStyles.secondary,
                          ),
                        )
                      else if (appsLoading)
                        const Padding(
                          padding: EdgeInsets.all(KoboSpacing.md),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (appsError != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '俺のアプリを読み込めませんでした：$appsError',
                              style: const TextStyle(color: KoboColors.error),
                            ),
                            TextButton(
                              key: const Key('kobo-my-apps-retry'),
                              onPressed: onRetryApps,
                              child: const Text('再読み込み'),
                            ),
                          ],
                        )
                      else if (apps.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: KoboSpacing.md,
                          ),
                          child: Text(
                            'まだ自分のアプリがありません。「つくる」から追加できます。',
                            style: KoboTextStyles.secondary,
                          ),
                        )
                      else
                        ...apps.take(3).map((ManagedHostedApp app) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: KoboSpacing.sm,
                            ),
                            child: KoboAppListTile(
                              app: app,
                              onTap: () {
                                final ValueChanged<ManagedHostedApp>? handler =
                                    onAppSelected;
                                if (handler == null) {
                                  throw StateError(
                                    'My Apps tap requires an app navigation handler.',
                                  );
                                }
                                handler(app);
                              },
                            ),
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
