import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'builtin_apps.dart';
import 'builtin_webview.dart';
import 'girls_errors.dart';
import 'girls_group_home_page.dart';
import 'girls_apps_page.dart';
import 'girls_current_group_store.dart';
import 'girls_email_settings_page.dart';
import 'girls_footer_nav.dart';
import 'girls_groups_page.dart';
import 'girls_home_mascot_prompt.dart';
import 'girls_profile_page.dart';
import 'girls_scaffold.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _pink = Color(0xFFE79AAF);
const String _mascotAsset = 'assets/girls/cutouts/mascot_white.png';
const String _profileAsset = 'assets/girls/cutouts/profile.png';
const String _settingsAsset = 'assets/girls/cutouts/settings.png';
const String _sparkleAsset = 'assets/girls/cutouts/sparkle.png';
const String _memoCardAsset = 'assets/girls/home/cards/memo_card.png';
const String _minappchiCardAsset = 'assets/girls/home/cards/minappchi_card.png';
const String _novelCardAsset = 'assets/girls/home/cards/novel_card.png';
const String _groupCreateCardAsset =
    'assets/girls/home/cards/group_create_card.png';
const GirlsHomeMascotPromptResolver _mascotPromptResolver =
    GirlsHomeMascotPromptResolver();

enum _AccountAction { email, refresh, logout }

class GirlsHomePage extends StatefulWidget {
  const GirlsHomePage({
    required this.api,
    required this.session,
    required this.onLogout,
    this.currentGroup,
    this.onCurrentGroupChanged,
    this.currentGroupStore = const SharedPreferencesGirlsCurrentGroupStore(),
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;
  final HostedGroup? currentGroup;
  final ValueChanged<HostedGroup?>? onCurrentGroupChanged;
  final GirlsCurrentGroupStore currentGroupStore;

  @override
  State<GirlsHomePage> createState() => _GirlsHomePageState();
}

class _GirlsHomePageState extends State<GirlsHomePage> {
  List<HostedGroup>? _groups;
  HostedGroup? _currentGroup;
  GirlsHomeMascotPrompt? _mascotPrompt;
  bool _loadingGroups = false;
  bool _creatingGroup = false;
  bool _arrangingBuiltin = false;
  String? _groupError;

  BuiltInApp get _memoApp => _findBuiltin('memo');
  BuiltInApp get _minappchiApp => _findBuiltin('minappchi');
  BuiltInApp get _novelApp => _findBuiltin('novel-starter');

  BuiltInApp _findBuiltin(String id) =>
      builtInApps.firstWhere((BuiltInApp app) => app.id == id);

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.currentGroup;
    _loadGroups();
  }

  @override
  void didUpdateWidget(covariant GirlsHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGroup?.groupId != oldWidget.currentGroup?.groupId) {
      _currentGroup = widget.currentGroup;
    }
  }

  void _setCurrentGroup(HostedGroup? group) {
    if (_currentGroup?.groupId == group?.groupId) return;
    setState(() => _currentGroup = group);
    widget.onCurrentGroupChanged?.call(group);
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loadingGroups = true;
      _groupError = null;
      _mascotPrompt = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      final String? currentId =
          _currentGroup?.groupId ?? await widget.currentGroupStore.load();
      HostedGroup? currentGroup;
      if (currentId != null) {
        for (final HostedGroup group in groups) {
          if (group.groupId == currentId) {
            currentGroup = group;
            break;
          }
        }
      }

      GirlsHomeMascotPrompt? mascotPrompt;
      if (currentGroup != null) {
        final List<HostedMember> members = await widget.api.listMembers(
          accessToken: widget.session.accessToken,
          groupId: currentGroup.groupId,
        );
        final List<HostedGroupApp> apps = await widget.api.listGroupApps(
          accessToken: widget.session.accessToken,
          groupId: currentGroup.groupId,
        );
        final int customAppCount = apps
            .where((HostedGroupApp app) => app.builtinId == null)
            .length;
        mascotPrompt = _mascotPromptResolver.resolve(
          memberCount: members.length,
          customAppCount: customAppCount,
        );
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _currentGroup = currentGroup;
        _mascotPrompt = mascotPrompt;
      });
      if (currentId != null && currentGroup == null) {
        widget.onCurrentGroupChanged?.call(null);
      }
    } catch (error) {
      if (mounted) setState(() => _groupError = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _launchBuiltin(BuiltInApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BuiltInWebViewPage(
          appId: app.id,
          title: app.title,
          assetPath: app.assetPath,
        ),
      ),
    );
    if (!mounted) return;
    await _offerBuiltinArrangement(app);
  }

  Future<void> _offerBuiltinArrangement(BuiltInApp app) async {
    final bool? arrange = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFFFFFBF7),
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '✨ このアプリをアレンジする？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '「${app.title}」をコピーして、自分好みに変えられるよ。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF806B73),
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('girls-builtin-arrange-confirm'),
                onPressed: _arrangingBuiltin
                    ? null
                    : () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text(
                  'このアプリをアレンジする！',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                key: const Key('girls-builtin-arrange-later'),
                onPressed: _arrangingBuiltin
                    ? null
                    : () => Navigator.of(sheetContext).pop(false),
                child: const Text('またあとで'),
              ),
            ],
          ),
        ),
      ),
    );
    if (arrange != true || !mounted) return;
    await _arrangeBuiltin(app);
  }

  Future<void> _arrangeBuiltin(BuiltInApp app) async {
    if (_arrangingBuiltin) return;
    final HostedGroup? group = _currentGroup;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先にグループを選ぶと、アプリをアレンジできるよ。')),
      );
      return;
    }

    setState(() {
      _arrangingBuiltin = true;
      _groupError = null;
    });
    try {
      final List<HostedGroupApp> apps = await widget.api.listGroupApps(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
      );
      final List<HostedGroupApp> installed = apps
          .where(
            (HostedGroupApp candidate) =>
                candidate.sourceKind == 'builtin' &&
                candidate.builtinId == app.id,
          )
          .toList(growable: false);
      if (installed.length > 1) {
        throw StateError(
          'Group has duplicate built-in installations for ${app.id}.',
        );
      }

      final HostedGroupApp parent = installed.isEmpty
          ? await widget.api.installBuiltin(
              accessToken: widget.session.accessToken,
              groupId: group.groupId,
              builtinId: app.id,
            )
          : installed.single;
      final HostedGroupApp forked = await widget.api.forkApp(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
        appId: parent.appId,
        title: '${app.title} アレンジ',
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => GirlsAppDetailPage(
            api: widget.api,
            session: widget.session,
            appId: forked.appId,
          ),
        ),
      );
      if (mounted) await _loadGroups();
    } catch (error) {
      if (mounted) setState(() => _groupError = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _arrangingBuiltin = false);
    }
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => GirlsGroupsPage(
          api: widget.api,
          session: widget.session,
          onHome: () => Navigator.of(routeContext).pop(),
          selectedGroupId: _currentGroup?.groupId,
          onGroupSelected: _setCurrentGroup,
          onLogout: () {
            Navigator.of(routeContext).pop();
            widget.onLogout();
          },
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _openApps() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => GirlsAppsPage(
          api: widget.api,
          session: widget.session,
          onHome: () => Navigator.of(routeContext).pop(),
          onGroups: _openGroups,
          currentGroup: _currentGroup,
          onCurrentGroupChanged: _setCurrentGroup,
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsProfilePage(
          api: widget.api,
          session: widget.session,
        ),
      ),
    );
  }

  Future<void> _openGroup(HostedGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsGroupHomePage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _openMascotPrompt(GirlsHomeMascotPrompt prompt) {
    switch (prompt.destination) {
      case GirlsHomeMascotDestination.invite:
        final HostedGroup? group = _currentGroup;
        if (group == null) {
          throw StateError('Invite mascot prompt requires a current group.');
        }
        return _showCurrentGroupId(group);
      case GirlsHomeMascotDestination.currentGroup:
        final HostedGroup? group = _currentGroup;
        if (group == null) {
          throw StateError('Play mascot prompt requires a current group.');
        }
        return _openGroup(group);
      case GirlsHomeMascotDestination.apps:
        return _openApps();
    }
  }

  Future<void> _showCurrentGroupId(HostedGroup group) async {
    try {
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
      );
      if (!mounted) return;
      await _showGroupId(invite);
    } catch (error) {
      if (mounted) setState(() => _groupError = girlsMessageFor(error));
    }
  }

  Future<String?> _askForGroupName() {
    String value = '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('💗 新しいグループ'),
        content: TextField(
          key: const Key('girls-group-name'),
          maxLength: maxHostedGroupNameLength,
          autocorrect: true,
          enableSuggestions: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'グループ名',
            hintText: '例：放課後イラスト部',
          ),
          onChanged: (String nextValue) => value = nextValue,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: const Text('つくる'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupId(HostedInvite invite) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('🎀 友達を招待しよう'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'このグループIDを友達に送ってね。友達は「グループ」→「グループを探す」から入力できます。',
            ),
            const SizedBox(height: 14),
            SelectableText(
              invite.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _lavender,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'このグループIDは変わりません。いつでも同じIDを使えます。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8C7893)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('グループIDをコピー'),
            ),
          ],
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroupFromHome() async {
    if (_creatingGroup) return;
    final String? rawName = await _askForGroupName();
    if (rawName == null || !mounted) return;
    final String name = rawName.trim();
    if (name.isEmpty) return;

    setState(() {
      _creatingGroup = true;
      _groupError = null;
    });

    late final HostedGroup createdGroup;
    try {
      createdGroup = await widget.api.createGroup(
        accessToken: widget.session.accessToken,
        name: name,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _creatingGroup = false;
          _groupError = girlsMessageFor(error);
        });
      }
      return;
    }

    try {
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: createdGroup.groupId,
      );
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      if (!mounted) return;
      setState(() => _groups = groups);
      await _showGroupId(invite);
      if (!mounted) return;
      await _openGroup(createdGroup);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _groupError =
            'グループ「${createdGroup.name}」は作成できたけれど、グループIDの取得に失敗しました。${girlsMessageFor(error)}';
      });
    } finally {
      if (mounted) setState(() => _creatingGroup = false);
    }
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
      builder: (BuildContext context) => SafeArea(
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
                leading:
                    const Icon(Icons.alternate_email_rounded, color: _pink),
                title: const Text('メールアドレス'),
                subtitle: const Text('確認コードで紐づける'),
                onTap: () => Navigator.of(context).pop(_AccountAction.email),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: _lavender),
                title: const Text('最新の情報に更新'),
                onTap: () => Navigator.of(context).pop(_AccountAction.refresh),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: _pink),
                title: const Text('ログアウト'),
                onTap: () => Navigator.of(context).pop(_AccountAction.logout),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _AccountAction.email:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => GirlsEmailSettingsPage(
              api: widget.api,
              session: widget.session,
            ),
          ),
        );
      case _AccountAction.refresh:
        await _loadGroups();
      case _AccountAction.logout:
        widget.onLogout();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroup>? groups = _groups;
    final GirlsHomeMascotPrompt? mascotPrompt = _mascotPrompt;
    return GirlsScaffold(
      leading: _BellButton(onTap: _showNotices),
      actions: <Widget>[
        _RoundArtButton(
          key: const Key('girls-home-settings'),
          assetName: _settingsAsset,
          label: '設定',
          onTap: _showAccountMenu,
        ),
        _RoundArtButton(
          key: const Key('girls-home-profile'),
          assetName: _profileAsset,
          label: 'マイページ',
          onTap: _openProfile,
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (mascotPrompt != null) ...<Widget>[
                    _MascotPromptCard(
                      prompt: mascotPrompt,
                      onTap: () => _openMascotPrompt(mascotPrompt),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const _SectionHeading(title: '公式アプリ'),
                  const SizedBox(height: 8),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                    children: <Widget>[
                      _HomeMenuCard(
                        key: const Key('girls-home-memo-app'),
                        assetName: _memoCardAsset,
                        label: 'マイメモ帳',
                        onTap: () => _launchBuiltin(_memoApp),
                      ),
                      _HomeMenuCard(
                        key: const Key('girls-home-minappchi-app'),
                        assetName: _minappchiCardAsset,
                        label: 'みんアプっち',
                        onTap: () => _launchBuiltin(_minappchiApp),
                      ),
                      _HomeMenuCard(
                        key: const Key('girls-home-novel-app'),
                        assetName: _novelCardAsset,
                        label: 'パステルノベル',
                        onTap: () => _launchBuiltin(_novelApp),
                      ),
                      _HomeMenuCard(
                        key: const Key('girls-home-groups'),
                        assetName: _groupCreateCardAsset,
                        label: 'グループと友達を招待',
                        onTap: _createGroupFromHome,
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  const _SectionHeading(title: '友達の最新情報'),
                  const SizedBox(height: 8),
                  if (_loadingGroups && groups == null)
                    const _LatestLoadingCard()
                  else if (_groupError != null)
                    _LatestErrorCard(
                      message: _groupError!,
                      onRetry: _loadGroups,
                    )
                  else
                    _LatestGroupCard(
                      group: _currentGroup,
                      onTap: _currentGroup == null
                          ? _openGroups
                          : () => _openGroup(_currentGroup!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: GirlsFooterNav(
        selectedTab: GirlsFooterTab.home,
        enabledTabs: const <GirlsFooterTab>{
          GirlsFooterTab.home,
          GirlsFooterTab.groups,
          GirlsFooterTab.apps,
          GirlsFooterTab.more,
        },
        onSelected: (GirlsFooterTab tab) {
          if (tab == GirlsFooterTab.groups) {
            _openGroups();
            return;
          }
          if (tab == GirlsFooterTab.apps || tab == GirlsFooterTab.more) {
            _openApps();
          }
        },
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

class _MascotPromptCard extends StatelessWidget {
  const _MascotPromptCard({required this.prompt, required this.onTap});

  final GirlsHomeMascotPrompt prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: prompt.message,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('girls-home-mascot-prompt'),
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Image.asset(
                  _mascotAsset,
                  key: const Key('girls-home-mascot-image'),
                  width: 62,
                  height: 66,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Positioned(
                        left: -5,
                        child: Transform.rotate(
                          angle: .785398,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBF7),
                              border: Border.all(
                                color: const Color(0xFFE7B5C8),
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBF7),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFE7B5C8),
                            width: 1.2,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x18A36B8A),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                prompt.message,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: _lavender,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Image.asset(_sparkleAsset, width: 25, height: 25),
        const SizedBox(width: 5),
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HomeMenuCard extends StatelessWidget {
  const _HomeMenuCard({
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
    return Center(
      child: FractionallySizedBox(
        widthFactor: .92,
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Image.asset(
                  assetName,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestGroupCard extends StatelessWidget {
  const _LatestGroupCard({required this.group, required this.onTap});
  final HostedGroup? group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HostedGroup? currentGroup = group;
    return Material(
      color: Colors.white.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 12, 10),
          child: Row(
            children: <Widget>[
              Image.asset(
                _mascotAsset,
                width: 46,
                height: 49,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      currentGroup == null ? 'まだ最新情報はないよ' : currentGroup.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      currentGroup == null
                          ? '友達を招待して、いっしょに遊ぼう！'
                          : 'みんなのアプリを見に行こう！',
                      style: const TextStyle(
                        color: Color(0xFF8A716C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _lavender),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestLoadingCard extends StatelessWidget {
  const _LatestLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 72,
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _LatestErrorCard extends StatelessWidget {
  const _LatestErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFC5CE)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA04455),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'もう一度',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}
