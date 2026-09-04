import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'builtin_apps.dart';
import 'builtin_webview.dart';
import 'girls_app_core.dart' as core;
import 'girls_apps_page.dart';
import 'girls_footer_nav.dart';
import 'girls_email_settings_page.dart';
import 'girls_groups_page.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _pink = Color(0xFFE79AAF);
const Color _cream = Color(0xFFFFFAF0);

const String _logoAsset = 'assets/girls/generated/minapp_girls_logo.png';
const String _patternAsset = 'assets/girls/cutouts/home_pattern.png';
const String _laceTopAsset = 'assets/girls/cutouts/lace_top.png';
const String _laceBottomAsset = 'assets/girls/cutouts/lace_bottom.png';
const String _mascotAsset = 'assets/girls/cutouts/mascot_white.png';
const String _profileAsset = 'assets/girls/cutouts/profile.png';
const String _settingsAsset = 'assets/girls/cutouts/settings.png';
const String _flowerAsset = 'assets/girls/cutouts/flower_pink.png';
const String _sparkleAsset = 'assets/girls/cutouts/sparkle.png';
const String _mascotDiaryCardAsset =
    'assets/girls/cutouts/mascot_diary_card.png';
const String _pastelNovelCardAsset =
    'assets/girls/cutouts/pastel_novel_card.png';
const String _pastelPaintCardAsset =
    'assets/girls/cutouts/pastel_paint_card.png';
const String _groupCreateCardAsset =
    'assets/girls/cutouts/group_create_card.png';

enum _AccountAction { email, refresh, logout }

/// The Girls landing screen. It keeps the playful visual hierarchy from the
/// supplied concept art while routing every live destination to the existing
/// app and group flows.
class GirlsHomePage extends StatefulWidget {
  const GirlsHomePage({
    required this.api,
    required this.session,
    required this.onLogout,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback onLogout;

  @override
  State<GirlsHomePage> createState() => _GirlsHomePageState();
}

class _GirlsHomePageState extends State<GirlsHomePage> {
  List<HostedGroup>? _groups;
  bool _loadingGroups = false;
  bool _creatingGroup = false;
  String? _groupError;

  BuiltInApp get _mascotApp => _findBuiltin('shiba-goshujin');
  BuiltInApp get _novelApp => _findBuiltin('novel-starter');
  BuiltInApp get _paintApp => _findBuiltin('ol-home');

  BuiltInApp _findBuiltin(String id) =>
      builtInApps.firstWhere((BuiltInApp app) => app.id == id);

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loadingGroups = true;
      _groupError = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      if (mounted) setState(() => _groups = groups);
    } catch (error) {
      if (mounted) setState(() => _groupError = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Future<void> _launchBuiltin(BuiltInApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BuiltInWebViewPage(
          title: app.title,
          assetPath: app.assetPath,
        ),
      ),
    );
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => GirlsGroupsPage(
          api: widget.api,
          session: widget.session,
          onHome: () => Navigator.of(routeContext).pop(),
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
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _openGroup(HostedGroup group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => core.GirlsGroupHomePage(
          api: widget.api,
          session: widget.session,
          group: group,
        ),
      ),
    );
    if (mounted) await _loadGroups();
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
          onChanged: (String nextValue) {
            value = nextValue;
          },
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
        title: const Text('🎀 グループIDができたよ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('友達はGirlsの「グループIDで参加」からこのIDを入力すると参加できます。'),
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
              '7日間有効です。新しいIDを発行すると前のIDは使えなくなります。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8C7893)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('IDをコピー'),
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
        setState(() => _groupError = core.girlsMessageFor(error));
      }
      return;
    } finally {
      if (!mounted) return;
    }

    try {
      final HostedInvite invite = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: createdGroup.groupId,
      );
      await _loadGroups();
      if (!mounted) return;
      await _showGroupId(invite);
      if (!mounted) return;
      await _openGroup(createdGroup);
    } catch (error) {
      if (!mounted) return;
      try {
        await _loadGroups();
      } catch (reloadError) {
        if (!mounted) return;
        setState(() {
          _groupError =
              'グループ「${createdGroup.name}」は作成できたけれど、グループIDの発行に失敗し、その後の一覧更新にも失敗しました。${core.girlsMessageFor(error)} / ${core.girlsMessageFor(reloadError)}';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _groupError =
            'グループ「${createdGroup.name}」は作成できたけれど、グループIDの発行に失敗しました。${core.girlsMessageFor(error)}';
      });
    } finally {
      if (mounted) setState(() => _creatingGroup = false);
    }
  }

  void _showNotices() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新しいお知らせはまだないよ♡')),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onTap: () => Navigator.of(context).pop(_AccountAction.email),
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: _lavender),
                title: const Text('最新の情報に更新'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onTap: () => Navigator.of(context).pop(_AccountAction.refresh),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: _pink),
                title: const Text('ログアウト'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
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
    return Scaffold(
      backgroundColor: _cream,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: _cream,
          image: DecorationImage(
            image: AssetImage(_patternAsset),
            fit: BoxFit.cover,
            opacity: .12,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _GirlsHomeHeader(
                onNotices: _showNotices,
                onSettings: _showAccountMenu,
                onProfile: _showAccountMenu,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const _WelcomeCard(),
                          const SizedBox(height: 16),
                          const _SectionHeading(title: 'ビルトインアプリ'),
                          const SizedBox(height: 8),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 1.04,
                            children: <Widget>[
                              _HomeMenuCard(
                                key: const Key('girls-home-mascot-app'),
                                assetName: _mascotDiaryCardAsset,
                                label: 'マスコット付き交換日記',
                                onTap: () => _launchBuiltin(_mascotApp),
                              ),
                              _HomeMenuCard(
                                key: const Key('girls-home-novel-app'),
                                assetName: _pastelNovelCardAsset,
                                label: 'パステルノベル',
                                onTap: () => _launchBuiltin(_novelApp),
                              ),
                              _HomeMenuCard(
                                key: const Key('girls-home-paint-app'),
                                assetName: _pastelPaintCardAsset,
                                label: 'パステルお絵かき',
                                onTap: () => _launchBuiltin(_paintApp),
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
                              group: groups?.firstOrNull,
                              onTap: groups == null || groups.isEmpty
                                  ? _openGroups
                                  : () => _openGroup(groups.first),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: GirlsFooterNav(
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
      ),
    );
  }
}

class _GirlsHomeHeader extends StatelessWidget {
  const _GirlsHomeHeader({
    required this.onNotices,
    required this.onSettings,
    required this.onProfile,
  });

  final VoidCallback onNotices;
  final VoidCallback onSettings;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFF8EF),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
          child: Row(
            children: <Widget>[
              _BellButton(onTap: onNotices),
              Expanded(
                child: Center(
                  child: Image.asset(
                    _logoAsset,
                    width: 88,
                    height: 46,
                    fit: BoxFit.contain,
                    semanticLabel: 'みんアプ Girls',
                  ),
                ),
              ),
              _RoundArtButton(
                key: const Key('girls-home-settings'),
                assetName: _settingsAsset,
                label: '設定',
                onTap: onSettings,
              ),
              _RoundArtButton(
                assetName: _profileAsset,
                label: 'マイページ',
                onTap: onProfile,
              ),
            ],
          ),
        ),
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
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .82),
        side: const BorderSide(color: Color(0xFFF2C8D6)),
      ),
      icon: const Icon(
        Icons.notifications_rounded,
        color: Color(0xFFC57B98),
        size: 21,
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
        radius: 21,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Image.asset(
            assetName,
            width: 35,
            height: 35,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF1E6), Color(0xFFFFE4EC)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1FC7829B),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 5,
            bottom: -2,
            child: Image.asset(
              _mascotAsset,
              width: 112,
              height: 126,
              fit: BoxFit.contain,
              semanticLabel: '白い猫のハニー',
            ),
          ),
          Positioned(
            top: 9,
            left: 10,
            child: Image.asset(_flowerAsset, width: 27, height: 27),
          ),
          Positioned(
            right: 10,
            top: 31,
            child: _SpeechBubble(
              width: MediaQuery.sizeOf(context).width < 355 ? 180 : 208,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              _laceTopAsset,
              height: 18,
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              _laceBottomAsset,
              height: 19,
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          left: -5,
          bottom: 20,
          child: Transform.rotate(
            angle: .78,
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFD9B3A8)),
                  bottom: BorderSide(color: Color(0xFFD9B3A8)),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: const Color(0xFFD9B3A8), width: 1.4),
          ),
          child: const Text(
            'こんにちは、ハニー！\n今日も楽しもうね♪',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
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
    return Semantics(
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
