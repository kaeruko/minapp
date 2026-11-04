import 'package:flutter/material.dart';

import '../builtin_apps.dart';
import '../builtin_webview.dart';
import '../hosted_guest_access.dart';
import 'girls_footer_nav.dart';
import 'girls_scaffold.dart';
import 'girls_shop_page.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const String _memoCardAsset = 'assets/girls/home/cards/memo_card.png';
const String _minappchiCardAsset = 'assets/girls/home/cards/minappchi_card.png';
const String _novelCardAsset = 'assets/girls/home/cards/novel_card.png';

/// Login-free Girls entrance with bundled local apps and public shop browsing.
class GirlsGuestHomePage extends StatelessWidget {
  const GirlsGuestHomePage({required this.api, super.key});

  final HostedGirlsApi api;

  BuiltInApp _builtin(String id) =>
      builtInApps.firstWhere((BuiltInApp app) => app.id == id);

  Future<void> _requireAccount(
    BuildContext context, {
    required String feature,
  }) {
    return HostedGuestAccessScope.requireAuthentication(
      context,
      feature: feature,
    );
  }

  Future<void> _launchBuiltin(BuildContext context, BuiltInApp app) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: GirlsPageRouteSettings(
          headerLaceBackgroundColor: app.topBackgroundColor,
        ),
        builder: (BuildContext context) => BuiltInWebViewPage(
          appId: app.id,
          title: app.title,
          assetPath: app.assetPath,
        ),
      ),
    );
  }

  Future<void> _openShop(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsShopPage(
          api: api,
          session: null,
          currentGroup: null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BuiltInApp memo = _builtin('memo');
    final BuiltInApp minappchi = _builtin('minappchi');
    final BuiltInApp novel = _builtin('novel-starter');
    return GirlsScaffold(
      title: 'ホーム',
      actions: <Widget>[
        IconButton(
          key: const Key('girls-guest-auth'),
          onPressed: () => HostedGuestAccessScope.openAuthentication(context),
          icon: const Icon(Icons.login_rounded, color: _lavender),
          tooltip: '登録・ログイン',
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Square artwork plus a separate caption below each image.
                  childAspectRatio: 0.8,
                  children: <Widget>[
                    _GuestAppCard(
                      key: const Key('girls-guest-memo'),
                      assetName: _memoCardAsset,
                      label: 'マイメモ帳',
                      onTap: () => _launchBuiltin(context, memo),
                    ),
                    _GuestAppCard(
                      key: const Key('girls-guest-minappchi'),
                      assetName: _minappchiCardAsset,
                      label: 'みんアプっち',
                      onTap: () => _launchBuiltin(context, minappchi),
                    ),
                    _GuestAppCard(
                      key: const Key('girls-guest-novel'),
                      assetName: _novelCardAsset,
                      label: 'パステルノベル',
                      onTap: () => _launchBuiltin(context, novel),
                    ),
                    _GuestAccountCard(
                      onTap: () => _requireAccount(
                        context,
                        feature: 'アプリ作成や公開',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: GirlsFooterNav(
        selectedTab: GirlsFooterTab.home,
        enabledTabs: GirlsFooterTab.values.toSet(),
        onSelected: (GirlsFooterTab tab) {
          if (tab == GirlsFooterTab.home) return;
          if (tab == GirlsFooterTab.shop) {
            _openShop(context);
            return;
          }
          final String feature = switch (tab) {
            GirlsFooterTab.home => 'ホーム',
            GirlsFooterTab.groups => 'グループ',
            GirlsFooterTab.shop => 'ショップ',
            GirlsFooterTab.apps => 'アプリ作成や公開',
            GirlsFooterTab.more => 'マイページ',
          };
          _requireAccount(context, feature: feature);
        },
      ),
    );
  }
}

class _GuestAppCard extends StatelessWidget {
  const _GuestAppCard({
    required this.assetName,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String assetName;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Image.asset(
                  assetName,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestAccountCard extends StatelessWidget {
  const _GuestAccountCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('girls-guest-account-feature'),
      color: const Color(0xFFF5EEFF),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.add_circle_outline_rounded,
                  color: _lavender, size: 34),
              SizedBox(height: 6),
              Text(
                '作る・公開する',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '登録すると使えます',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFF8C7893), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
