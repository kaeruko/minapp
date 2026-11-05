import 'package:flutter/material.dart';

import '../api.dart';
import '../hosted_consumer_api.dart';
import '../hosted_consumer_errors.dart';
import '../hosted_guest_access.dart';
import 'kobo_account_settings_page.dart';
import 'kobo_apps_page.dart';
import 'kobo_components.dart';
import 'kobo_home_page.dart';
import 'kobo_models.dart';
import 'kobo_shop_page.dart';
import 'kobo_theme.dart';

class KoboShell extends StatefulWidget {
  const KoboShell({
    required this.api,
    required this.session,
    required this.onLogout,
    super.key,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession? session;
  final Future<void> Function()? onLogout;

  @override
  State<KoboShell> createState() => _KoboShellState();
}

class _KoboShellState extends State<KoboShell> {
  KoboNavigationItem _selected = KoboNavigationItem.home;
  String _shopSearchQuery = '';

  void _openFeaturedCategory(KoboCategory category) {
    setState(() {
      _shopSearchQuery = category.title;
      _selected = KoboNavigationItem.community;
    });
  }

  void _select(KoboNavigationItem item) {
    if (item == KoboNavigationItem.create && widget.session == null) {
      HostedGuestAccessScope.requireAuthentication(
        context,
        feature: 'アプリを作る機能',
      );
      return;
    }
    setState(() {
      // A normal navigation to the catalog must not keep the featured
      // card's search filter from an earlier visit.
      if (item == KoboNavigationItem.community) _shopSearchQuery = '';
      _selected = item;
    });
  }

  void _openCreate() {
    if (widget.session == null) {
      HostedGuestAccessScope.requireAuthentication(
        context,
        feature: 'アプリを作る機能',
      );
      return;
    }
    setState(() => _selected = KoboNavigationItem.create);
  }

  void _openMyApps() {
    if (widget.session == null) {
      HostedGuestAccessScope.requireAuthentication(
        context,
        feature: '俺のアプリ',
      );
      return;
    }
    setState(() => _selected = KoboNavigationItem.create);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_selected) {
      KoboNavigationItem.home => KoboHomePage(
          onCreate: _openCreate,
          onViewAllApps: _openMyApps,
          onCategorySelected: _openFeaturedCategory,
          onNavigationSelected: _select,
        ),
      KoboNavigationItem.community => KoboShopPage(
          api: widget.api,
          session: widget.session,
          initialSearchQuery: _shopSearchQuery,
          onNavigationSelected: _select,
        ),
      KoboNavigationItem.create => KoboAppsPage(
          api: widget.api,
          session: widget.session!,
          onNavigationSelected: _select,
        ),
      KoboNavigationItem.profile => _KoboProfilePage(
          api: widget.api,
          session: widget.session,
          onLogout: widget.onLogout,
          onNavigationSelected: _select,
        ),
    };
  }
}

class _KoboProfilePage extends StatefulWidget {
  const _KoboProfilePage({
    required this.api,
    required this.session,
    required this.onLogout,
    required this.onNavigationSelected,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession? session;
  final Future<void> Function()? onLogout;
  final ValueChanged<KoboNavigationItem> onNavigationSelected;

  @override
  State<_KoboProfilePage> createState() => _KoboProfilePageState();
}

class _KoboProfilePageState extends State<_KoboProfilePage> {
  bool _busy = false;

  Future<void> _authenticate() {
    return HostedGuestAccessScope.openAuthentication(context);
  }

  Future<void> _logout() async {
    final Future<void> Function()? logout = widget.onLogout;
    if (logout == null || _busy) return;
    setState(() => _busy = true);
    try {
      await logout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hostedConsumerMessageFor(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAccountSettings() async {
    final AuthenticatedSession? session = widget.session;
    final Future<void> Function()? logout = widget.onLogout;
    if (session == null || logout == null) {
      throw StateError(
        'Account settings require an authenticated session and logout action.',
      );
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => KoboAccountSettingsPage(
          api: widget.api,
          session: session,
          onAccountDeleted: logout,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool guest = widget.session == null;
    return Scaffold(
      appBar: AppBar(title: const Text('マイページ')),
      body: ListView(
        padding: const EdgeInsets.all(KoboSpacing.md),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(KoboSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        guest ? Icons.person_outline : Icons.badge_outlined,
                        size: 52,
                        color: KoboColors.navy,
                      ),
                      const SizedBox(height: KoboSpacing.md),
                      Text(
                        guest ? 'ゲストで利用中' : '工房にログイン中',
                        textAlign: TextAlign.center,
                        style: KoboTextStyles.sectionTitle,
                      ),
                      const SizedBox(height: KoboSpacing.sm),
                      Text(
                        guest
                            ? '公開アプリはそのまま遊べます。登録すると、自分の道具を作ったり管理したりできます。'
                            : '表示名やメール、必要なときだけ使う非公開グループを管理できます。',
                        textAlign: TextAlign.center,
                        style: KoboTextStyles.body,
                      ),
                      const SizedBox(height: KoboSpacing.lg),
                      if (guest)
                        FilledButton.icon(
                          key: const Key('kobo-open-auth'),
                          onPressed: _authenticate,
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('登録・ログイン'),
                        )
                      else ...<Widget>[
                        FilledButton.icon(
                          key: const Key('kobo-account-settings'),
                          onPressed: _busy ? null : _openAccountSettings,
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('アカウント設定'),
                        ),
                        const SizedBox(height: KoboSpacing.sm),
                        OutlinedButton.icon(
                          key: const Key('kobo-logout'),
                          onPressed: _busy ? null : _logout,
                          icon: const Icon(Icons.logout_rounded),
                          label: Text(_busy ? 'ログアウト中…' : 'ログアウト'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: KoboBottomNavigation(
        selectedItem: KoboNavigationItem.profile,
        onSelected: widget.onNavigationSelected,
      ),
    );
  }
}
