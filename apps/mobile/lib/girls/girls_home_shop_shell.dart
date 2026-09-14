import 'package:flutter/material.dart';

import '../api.dart';
import 'girls_apps_hub_page.dart';
import 'girls_current_group_store.dart';
import 'girls_email_settings_page.dart';
import 'girls_footer_nav.dart';
import 'girls_groups_dashboard_page.dart';
import 'girls_home_page.dart';
import 'girls_registration_onboarding.dart';
import 'girls_scaffold.dart';
import 'girls_shop_page.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _pink = Color(0xFFE79AAF);
const String _profileAsset = 'assets/girls/cutouts/profile.png';
const String _settingsAsset = 'assets/girls/cutouts/settings.png';

enum _AccountAction { email, refresh, logout }

/// One authenticated Girls chrome around the nested in-app navigator.
///
/// Every route pushed from Home / Groups / Shop / Apps stays inside this
/// navigator, so the branded header remains stable. The shared footer normally
/// stays stable too; a creative editor may explicitly hide it while its own
/// editor footer is active, then restore it when the flow closes.
class GirlsHomeShopShell extends StatefulWidget {
  const GirlsHomeShopShell({
    required this.api,
    required this.session,
    required this.onLogout,
    this.currentGroupStore = const SharedPreferencesGirlsCurrentGroupStore(),
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;
  final GirlsCurrentGroupStore currentGroupStore;

  @override
  State<GirlsHomeShopShell> createState() => _GirlsHomeShopShellState();
}

class _GirlsHomeShopShellState extends State<GirlsHomeShopShell> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  GirlsFooterTab _selectedTab = GirlsFooterTab.home;
  HostedGroup? _currentGroup;
  bool _loadingCurrentGroup = true;
  bool _footerHidden = false;
  String? _currentGroupError;

  @override
  void initState() {
    super.initState();
    _loadCurrentGroup();
  }

  Future<void> _loadCurrentGroup() async {
    setState(() {
      _loadingCurrentGroup = true;
      _currentGroupError = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      final String? storedGroupId = await widget.currentGroupStore.load();
      HostedGroup? currentGroup;

      if (storedGroupId != null) {
        for (final HostedGroup group in groups) {
          if (group.groupId == storedGroupId) {
            currentGroup = group;
            break;
          }
        }
        // Keep an unavailable stored id intact. It must never turn into an
        // implicit switch to another membership on a later app restart.
      } else {
        if (groups.length == 1) {
          currentGroup = groups.single;
        } else {
          final List<HostedGroup> starterGroups = groups
              .where(
                (HostedGroup group) =>
                    group.isOwner && group.name == girlsInitialGroupName,
              )
              .toList(growable: false);
          if (starterGroups.length == 1) {
            currentGroup = starterGroups.single;
          }
        }
        if (currentGroup != null) {
          await widget.currentGroupStore.save(currentGroup.groupId);
        }
      }

      if (!mounted) return;
      setState(() {
        _currentGroup = currentGroup;
        _loadingCurrentGroup = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _currentGroupError = error.toString();
        _loadingCurrentGroup = false;
      });
    }
  }

  void _setCurrentGroup(HostedGroup? group) {
    if (_currentGroup?.groupId == group?.groupId) return;
    setState(() => _currentGroup = group);
  }

  void _setFooterHidden(bool hidden) {
    if (!mounted || _footerHidden == hidden) return;
    setState(() => _footerHidden = hidden);
  }

  Route<void> _rootRoute(GirlsFooterTab tab) {
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: '/girls/${tab.name}'),
      builder: (BuildContext routeContext) {
        return switch (tab) {
          GirlsFooterTab.home => GirlsHomePage(
              api: widget.api,
              session: widget.session,
              onLogout: widget.onLogout,
              currentGroup: _currentGroup,
              onCurrentGroupChanged: _setCurrentGroup,
            ),
          GirlsFooterTab.groups => GirlsGroupsDashboardPage(
              api: widget.api,
              session: widget.session,
              currentGroup: _currentGroup,
              onCurrentGroupChanged: _setCurrentGroup,
              currentGroupStore: widget.currentGroupStore,
            ),
          GirlsFooterTab.shop => GirlsShopPage(
              api: widget.api,
              session: widget.session,
            ),
          GirlsFooterTab.apps => GirlsAppsPage(
              api: widget.api,
              session: widget.session,
              onHome: () => _selectTab(GirlsFooterTab.home),
              onGroups: () => _selectTab(GirlsFooterTab.groups),
              currentGroup: _currentGroup,
              onCurrentGroupChanged: _setCurrentGroup,
              onFooterVisibilityChanged: _setFooterHidden,
            ),
          // 「その他」の専用画面ができるまでは従来どおりアプリ画面を使う。
          GirlsFooterTab.more => GirlsAppsPage(
              api: widget.api,
              session: widget.session,
              onHome: () => _selectTab(GirlsFooterTab.home),
              onGroups: () => _selectTab(GirlsFooterTab.groups),
              currentGroup: _currentGroup,
              onCurrentGroupChanged: _setCurrentGroup,
              onFooterVisibilityChanged: _setFooterHidden,
            ),
        };
      },
    );
  }

  void _selectTab(GirlsFooterTab tab) {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    setState(() {
      _selectedTab = tab;
      _footerHidden = false;
    });
    navigator.pushAndRemoveUntil(_rootRoute(tab), (Route<dynamic> route) => false);
  }

  void _showNotices() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新しいお知らせはまだないよ')),
    );
  }

  Future<void> _showAccountMenu() async {
    final _AccountAction? action = await showModalBottomSheet<_AccountAction>(
      context: context,
      backgroundColor: const Color(0xFFFFFBF7),
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '設定',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const Key('girls-settings-email'),
                leading: const Icon(
                  Icons.alternate_email_rounded,
                  color: _pink,
                ),
                title: const Text('メールアドレス'),
                subtitle: const Text('確認コードで紐づける'),
                onTap: () => Navigator.of(sheetContext).pop(_AccountAction.email),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: _lavender),
                title: const Text('最新の情報に更新'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AccountAction.refresh),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: _pink),
                title: const Text('ログアウト'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AccountAction.logout),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;

    switch (action) {
      case _AccountAction.email:
        await _navigatorKey.currentState?.push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => GirlsEmailSettingsPage(
              api: widget.api,
              session: widget.session,
            ),
          ),
        );
      case _AccountAction.refresh:
        await _loadCurrentGroup();
        if (mounted) _selectTab(_selectedTab);
      case _AccountAction.logout:
        widget.onLogout();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCurrentGroup) {
      return const GirlsScaffold(
        body: Center(child: CircularProgressIndicator()),
        bottomNavigationBar: SizedBox.shrink(),
      );
    }

    final String? currentGroupError = _currentGroupError;
    if (currentGroupError != null) {
      return GirlsScaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  color: _lavender,
                  size: 42,
                ),
                const SizedBox(height: 12),
                const Text(
                  'いまのグループを確認できませんでした',
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(currentGroupError, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _loadCurrentGroup,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('もう一度確認'),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: const SizedBox.shrink(),
      );
    }

    return GirlsScaffold(
      leading: _BellButton(onTap: _showNotices),
      actions: <Widget>[
        _RoundArtButton(
          key: const Key('girls-shell-settings'),
          assetName: _settingsAsset,
          label: '設定',
          onTap: _showAccountMenu,
        ),
        _RoundArtButton(
          key: const Key('girls-shell-profile'),
          assetName: _profileAsset,
          label: 'マイページ',
          onTap: _showAccountMenu,
        ),
      ],
      body: GirlsScaffoldChromeScope(
        child: Navigator(
          key: _navigatorKey,
          initialRoute: '/girls/home',
          onGenerateInitialRoutes: (
            NavigatorState navigator,
            String initialRoute,
          ) => <Route<void>>[_rootRoute(GirlsFooterTab.home)],
          onGenerateRoute: (RouteSettings settings) =>
              _rootRoute(GirlsFooterTab.home),
        ),
      ),
      bottomNavigationBar: _footerHidden
          ? const SizedBox.shrink()
          : GirlsFooterNav(
              selectedTab: _selectedTab,
              onSelected: _selectTab,
            ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'お知らせ',
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.notifications_rounded,
        color: Color(0xFFC57B98),
        size: 22,
      ),
    );
  }
}

class _RoundArtButton extends StatelessWidget {
  const _RoundArtButton({
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
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Image.asset(
              assetName,
              width: 30,
              height: 30,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}