import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'girls_app_core_legacy.dart' as core;
import 'girls_group_app_management_page.dart';
import 'girls_scaffold.dart';
import 'hosted_app_webview.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF8B6BB2);
const Color _panelPink = Color(0xFFF8DCDD);
const Color _softCream = Color(0xFFFFFBF6);
const String _groupHomeBackgroundAsset =
    'assets/girls/backgrounds/group_home_background.jpg';

class GirlsGroupHomePage extends StatefulWidget {
  const GirlsGroupHomePage({
    required this.api,
    required this.session,
    required this.group,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup group;

  @override
  State<GirlsGroupHomePage> createState() => _GirlsGroupHomePageState();
}

class _GirlsGroupHomePageState extends State<GirlsGroupHomePage> {
  List<HostedGroupApp>? _apps;
  bool _busy = false;
  String? _error;
  String? _launchingAppId;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroupApp> apps = await widget.api.listGroupApps(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showGroupId() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedInvite groupId = await widget.api.createInvite(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
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
              _GroupIdBox(code: groupId.code),
              const SizedBox(height: 8),
              const Text(
                'このグループIDは変わりません。いつでも同じIDを使えます。',
                style: TextStyle(fontSize: 12, color: Color(0xFF8C7893)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: groupId.code));
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
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launchHostedApp(HostedGroupApp app) async {
    if (!app.isPublished) {
      setState(() => _error = '「${app.title}」はまだ公開されていません。');
      return;
    }
    setState(() {
      _launchingAppId = app.appId;
      _error = null;
    });
    try {
      final launch = await widget.api.createLaunch(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage(
            title: app.title,
            launch: launch,
            runtimeTransport: widget.api.runtimeClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _launchingAppId = null);
    }
  }

  Future<void> _openManagedApp(HostedGroupApp app) async {
    if (!widget.group.isOwner || !app.editable) {
      throw StateError(
        'Group app management requires owner role and editable app.',
      );
    }
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => GirlsGroupAppManagementPage(
          api: widget.api,
          session: widget.session,
          group: widget.group,
          appId: app.appId,
        ),
      ),
    );
    if (changed == true && mounted) await _loadApps();
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroupApp>? apps = _apps;
    return GirlsScaffold(
      title: 'みんアプ Girls',
      pageBackgroundDecoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_groupHomeBackgroundAsset),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
      leading: IconButton(
        tooltip: '戻る',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: _lavender),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: '更新',
          onPressed: _busy ? null : _loadApps,
          icon: const Icon(Icons.refresh_rounded, color: _lavender),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _loadApps,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: <Widget>[
            _GroupHeaderCard(
              group: widget.group,
              busy: _busy,
              onInvite: _showGroupId,
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
            ],
            const SizedBox(height: 20),
            const Text(
              'このグループのアプリ',
              style: TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (apps == null)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (apps.isEmpty)
              const _EmptyAppsCard()
            else
              ...apps.map(
                (HostedGroupApp app) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AppTile(
                    app: app,
                    loading: _launchingAppId == app.appId,
                    onTap: () => _launchHostedApp(app),
                    onManage: widget.group.isOwner && app.editable
                        ? () => _openManagedApp(app)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const SizedBox.shrink(),
    );
  }
}

class _GroupHeaderCard extends StatelessWidget {
  const _GroupHeaderCard({
    required this.group,
    required this.busy,
    required this.onInvite,
  });

  final HostedGroup group;
  final bool busy;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFADADD), Color(0xFFE9D9FA)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(Icons.favorite_rounded, color: Color(0xFFE783A2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  group.isOwner ? 'あなたがオーナーです' : '参加中のグループ',
                  style: const TextStyle(color: Color(0xFF8A716C), fontSize: 12),
                ),
              ],
            ),
          ),
          if (onInvite != null)
            TextButton.icon(
              key: const Key('girls-group-invite'),
              onPressed: busy ? null : onInvite,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('友達を招待'),
            ),
        ],
      ),
    );
  }
}

class _GroupIdBox extends StatelessWidget {
  const _GroupIdBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3ECFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SelectableText(
        code,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _lavender,
          fontSize: 21,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.loading,
    required this.onTap,
    required this.onManage,
  });

  final HostedGroupApp app;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _softCream.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                backgroundColor: Color(0xFFDDF0DF),
                child: Icon(Icons.widgets_rounded, color: _lavender),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.isPublished ? 'タップして遊ぶ' : 'まだ公開されていません',
                      style: const TextStyle(
                        color: Color(0xFF8A716C),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onManage != null)
                IconButton(
                  tooltip: '管理',
                  onPressed: onManage,
                  icon: const Icon(Icons.settings_rounded, color: _lavender),
                ),
              const Icon(Icons.chevron_right_rounded, color: _lavender),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAppsCard extends StatelessWidget {
  const _EmptyAppsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelPink.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'このグループにはまだアプリがありません。',
        textAlign: TextAlign.center,
        style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE3E7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9F455D),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
