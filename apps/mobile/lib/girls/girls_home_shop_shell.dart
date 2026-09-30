import 'package:flutter/material.dart';

import '../api.dart';
import 'girls_account_deletion_page.dart';
import 'girls_apps_hub_page.dart';
import 'girls_apps_cache.dart';
import 'girls_current_group_store.dart';
import 'girls_email_settings_page.dart';
import 'girls_footer_nav.dart';
import 'girls_groups_dashboard_page.dart';
import 'girls_home_page.dart';
import 'girls_profile_page.dart';
import 'girls_registration_onboarding.dart';
import 'girls_scaffold.dart';
import 'girls_shop_page.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _pink = Color(0xFFE79AAF);
const String _profileAsset = 'assets/girls/cutouts/profile.png';
const String _settingsAsset = 'assets/girls/cutouts/settings.png';

enum _AccountAction { email, refresh, deleteAccount, logout }

/// One authenticated Girls chrome around the nested in-app navigator.
///
/// Every route pushed from Home / Groups / Shop / Apps stays inside this
/// navigator, so the branded header remains stable. The shared footer also
/// stays visible on a maker's project list. While a creative editor or its
/// nested preview is open, the shared footer is hidden so the editor can use
/// that area for its own controls.
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
  final GirlsAppsCache _appsCache = GirlsAppsCache();
  late final _GirlsShellNavigatorObserver _navigatorObserver;
  GirlsFooterTab _selectedTab = GirlsFooterTab.home;
  HostedGroup? _currentGroup;
  bool _loadingCurrentGroup = true;
  bool _footerHidden = false;
  bool _editorFooterReplacementActive = false;
  bool _novelFlowActive = false;
  int? _novelFlowBaseDepth;
  String? _currentGroupError;
  Color? _headerLaceBackgroundColor;

  @override
  void initState() {
    super.initState();
    _navigatorObserver = _GirlsShellNavigatorObserver(
      _syncFooterForRouteDepth,
      _syncHeaderLaceBackground,
    );
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
      final HostedGroup? currentGroup = resolveGirlsCurrentGroup(
        groups,
        storedGroupId: storedGroupId,
      );
      if (currentGroup != null && storedGroupId != currentGroup.groupId) {
        await widget.currentGroupStore.save(currentGroup.groupId);
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

  void _setEditorFooterReplacementActive(bool active) {
    if (!mounted || _editorFooterReplacementActive == active) return;
    setState(() => _editorFooterReplacementActive = active);
  }

  void _setNovelFlowActive(bool active) {
    if (!mounted) return;
    if (active) {
      if (!_novelFlowActive) {
        _novelFlowActive = true;
        _novelFlowBaseDepth = _navigatorObserver.depth;
      }
    } else {
      _novelFlowActive = false;
      _novelFlowBaseDepth = null;
    }
    _syncFooterForRouteDepth();
  }

  void _syncFooterForRouteDepth() {
    if (!mounted) return;
    final int? baseDepth = _novelFlowBaseDepth;
    final bool hidden = _novelFlowActive &&
        baseDepth != null &&
        _navigatorObserver.depth > baseDepth + 1;
    if (_footerHidden == hidden) return;
    setState(() => _footerHidden = hidden);
  }

  void _syncHeaderLaceBackground() {
    // Navigator can notify while building. Read the latest route after the
    // frame so rapid pushes/pops cannot leave an obsolete color behind.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Color? color = _navigatorObserver.headerLaceBackgroundColor;
      if (_headerLaceBackgroundColor == color) return;
      setState(() => _headerLaceBackgroundColor = color);
    });
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
              currentGroupStore: widget.currentGroupStore,
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
              currentGroup: _currentGroup,
              onGroupAppsChanged: _appsCache.clear,
            ),
          GirlsFooterTab.apps => GirlsAppsPage(
              cache: _appsCache,
              api: widget.api,
              session: widget.session,
              onHome: () => _selectTab(GirlsFooterTab.home),
              onGroups: () => _selectTab(GirlsFooterTab.groups),
              currentGroup: _currentGroup,
              onCurrentGroupChanged: _setCurrentGroup,
              onFooterVisibilityChanged: _setNovelFlowActive,
            ),
          // 「その他」の専用画面ができるまでは従来どおりアプリ画面を使う。
          GirlsFooterTab.more => GirlsAppsPage(
              cache: _appsCache,
              api: widget.api,
              session: widget.session,
              onHome: () => _selectTab(GirlsFooterTab.home),
              onGroups: () => _selectTab(GirlsFooterTab.groups),
              currentGroup: _currentGroup,
              onCurrentGroupChanged: _setCurrentGroup,
              onFooterVisibilityChanged: _setNovelFlowActive,
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
      _novelFlowActive = false;
      _novelFlowBaseDepth = null;
      _footerHidden = false;
      _editorFooterReplacementActive = false;
    });
    navigator.pushAndRemoveUntil(
        _rootRoute(tab), (Route<dynamic> route) => false);
  }

  void _showNotices() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新しいお知らせはまだないよ')),
    );
  }

  Future<void> _openProfile() async {
    setState(() {
      _novelFlowActive = false;
      _novelFlowBaseDepth = null;
      _footerHidden = false;
      _editorFooterReplacementActive = false;
    });
    await _navigatorKey.currentState?.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsProfilePage(
          api: widget.api,
          session: widget.session,
        ),
      ),
    );
    if (mounted) _selectTab(_selectedTab);
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
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AccountAction.email),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: _lavender),
                title: const Text('最新の情報に更新'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AccountAction.refresh),
              ),
              ListTile(
                key: const Key('girls-settings-delete-account'),
                leading: const Icon(
                  Icons.person_remove_rounded,
                  color: Color(0xFFB5465C),
                ),
                title: const Text(
                  'アカウントを削除',
                  style: TextStyle(color: Color(0xFFB5465C)),
                ),
                subtitle: const Text('アカウントと自分が所有するグループを完全に削除'),
                onTap: () => Navigator.of(sheetContext)
                    .pop(_AccountAction.deleteAccount),
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
        setState(() {
          _novelFlowActive = false;
          _novelFlowBaseDepth = null;
          _footerHidden = false;
          _editorFooterReplacementActive = false;
        });
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
      case _AccountAction.deleteAccount:
        setState(() {
          _novelFlowActive = false;
          _novelFlowBaseDepth = null;
          _footerHidden = false;
          _editorFooterReplacementActive = false;
        });
        final bool? deleted = await _navigatorKey.currentState?.push<bool>(
          MaterialPageRoute<bool>(
            builder: (BuildContext context) => GirlsAccountDeletionPage(
              api: widget.api,
              session: widget.session,
              currentGroupStore: widget.currentGroupStore,
            ),
          ),
        );
        if (deleted == true && mounted) {
          widget.onLogout();
        }
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

    final ThemeData shellTheme = Theme.of(context);
    final ThemeData nestedTheme = shellTheme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: shellTheme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );

    return GirlsScaffold(
      leading: _BellButton(onTap: _showNotices),
      headerLaceBackgroundColor: _headerLaceBackgroundColor,
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
          onTap: _openProfile,
        ),
      ],
      body: GirlsScaffoldChromeScope(
        onHome: () => _selectTab(GirlsFooterTab.home),
        onSharedFooterHiddenChanged: _setEditorFooterReplacementActive,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: Theme(
            data: nestedTheme,
            child: Navigator(
              key: _navigatorKey,
              observers: <NavigatorObserver>[_navigatorObserver],
              initialRoute: '/girls/home',
              onGenerateInitialRoutes: (
                NavigatorState navigator,
                String initialRoute,
              ) =>
                  <Route<void>>[_rootRoute(GirlsFooterTab.home)],
              onGenerateRoute: (RouteSettings settings) =>
                  _rootRoute(GirlsFooterTab.home),
            ),
          ),
        ),
      ),
      bottomNavigationBar:
          (_footerHidden || _editorFooterReplacementActive)
              ? const SizedBox.shrink()
              : GirlsFooterNav(
              selectedTab: _selectedTab,
              onSelected: _selectTab,
            ),
    );
  }
}

class _GirlsShellNavigatorObserver extends NavigatorObserver {
  _GirlsShellNavigatorObserver(this.onStackChanged, this.onTopChanged);

  final VoidCallback onStackChanged;
  final VoidCallback onTopChanged;
  Color? headerLaceBackgroundColor;
  int _depth = 0;

  int get depth => _depth;

  void _notify() {
    onStackChanged();
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    final RouteSettings settings = topRoute.settings;
    headerLaceBackgroundColor = settings is GirlsPageRouteSettings
        ? settings.headerLaceBackgroundColor
        : null;
    onTopChanged();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _depth += 1;
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_depth > 0) _depth -= 1;
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_depth > 0) _depth -= 1;
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _notify();
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
