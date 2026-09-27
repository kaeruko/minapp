import 'package:flutter/material.dart';

import '../api.dart';
import '../hosted_app_management_api.dart';
import '../hosted_app_webview.dart';
import '../ugc_safety.dart';
import 'girls_apps_page.dart';
import 'girls_errors.dart';
import 'girls_scaffold.dart';
import 'girls_shop_api.dart';
import 'hosted_girls_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const Color _pink = Color(0xFFE987A8);
const Color _cream = Color(0xFFFFFAF0);
const String _singAlongShopAppId = '9571adacf55c47b4ac772cd48621a08b';
const String _drawingShopAppId = 'ecb3cb6a08e05305668a952cbdae435b';
const String _singAlongCardAsset =
    'assets/girls/cutouts/minapp_cards_480/sing_along_card.png';
const String _drawingCardAsset =
    'assets/girls/cutouts/minapp_cards_480/drawing_card.png';

String? _shopArtworkAsset(GirlsShopApp app) {
  return switch (app.appId) {
    _singAlongShopAppId => _singAlongCardAsset,
    _drawingShopAppId => _drawingCardAsset,
    _ => null,
  };
}

String _shopDisplayTitle(GirlsShopApp app) {
  return switch (app.appId) {
    _drawingShopAppId => 'パステルおえかき',
    _ => app.title,
  };
}

class GirlsShopPage extends StatefulWidget {
  const GirlsShopPage({
    required this.api,
    required this.session,
    required this.currentGroup,
    this.onGroupAppsChanged,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup? currentGroup;
  final VoidCallback? onGroupAppsChanged;

  @override
  State<GirlsShopPage> createState() => _GirlsShopPageState();
}

class _GirlsShopPageState extends State<GirlsShopPage> {
  late final GirlsShopApi _shopApi;
  final CreatorSafetyStore _safetyStore = SharedPreferencesCreatorSafetyStore();
  final TextEditingController _searchController = TextEditingController();
  List<GirlsShopApp>? _apps;
  Set<String> _hiddenCreators = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shopApi = GirlsShopApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void dispose() {
    _shopApi.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Set<String> hidden =
          await _safetyStore.loadHiddenCreatorUserIds();
      final List<GirlsShopApp> apps =
          await _shopApi.listApps(widget.session.accessToken);
      if (!mounted) return;
      setState(() {
        _hiddenCreators = hidden;
        _apps = apps;
      });
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<GirlsShopApp> _visibleApps() {
    final String query = _searchController.text.trim().toLowerCase();
    return (_apps ?? const <GirlsShopApp>[]).where((GirlsShopApp app) {
      if (_hiddenCreators.contains(app.ownerUserId)) return false;
      if (query.isEmpty) return true;
      return app.title.toLowerCase().contains(query) ||
          app.ownerDisplayName.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _hideCreator(GirlsShopApp app) async {
    await _safetyStore.hideCreator(app.ownerUserId);
    if (!mounted) return;
    setState(() {
      _hiddenCreators = <String>{..._hiddenCreators, app.ownerUserId};
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<GirlsShopApp> apps = _visibleApps();
    return GirlsScaffold(
      title: 'みんアプGirls ショップ',
      leading: IconButton(
        tooltip: '戻る',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: _lavender),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: '更新',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, color: _lavender),
        ),
      ],
      bottomNavigationBar: const SizedBox.shrink(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9DDE8).withValues(alpha: .94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFF1BFD0)),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.storefront_rounded, color: _pink, size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ほかのグループのみんなが公開したアプリを見つけられるよ♡',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '作品名・作者名でさがす',
                prefixIcon: Icon(Icons.search_rounded, color: _lavender),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _GirlsShopError(message: _error!),
            ],
            const SizedBox(height: 18),
            if (_apps == null && _loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 54),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (apps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 46),
                child: Center(
                  child: Text(
                    'ショップの作品はまだないみたい…',
                    style: TextStyle(
                      color: Color(0xFF8C7893),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              for (final GirlsShopApp app in apps) ...<Widget>[
                _GirlsShopCard(
                  app: app,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => GirlsShopDetailPage(
                          api: widget.api,
                          shopApi: _shopApi,
                          session: widget.session,
                          app: app,
                          currentGroup: widget.currentGroup,
                          onGroupAppsChanged: widget.onGroupAppsChanged,
                          onHideCreator: _hideCreator,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 11),
              ],
          ],
        ),
      ),
    );
  }
}

class _GirlsShopCard extends StatelessWidget {
  const _GirlsShopCard({required this.app, required this.onTap});

  final GirlsShopApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: <Widget>[
              _GirlsShopArtwork(
                app: app,
                size: 58,
                radius: 18,
                iconSize: 28,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _shopDisplayTitle(app),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'by ${app.ownerDisplayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9B7F91),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _pink),
            ],
          ),
        ),
      ),
    );
  }
}

class GirlsShopDetailPage extends StatefulWidget {
  const GirlsShopDetailPage({
    required this.api,
    required this.shopApi,
    required this.session,
    required this.app,
    required this.currentGroup,
    this.onGroupAppsChanged,
    required this.onHideCreator,
    super.key,
  });

  final HostedGirlsApi api;
  final GirlsShopApi shopApi;
  final AuthenticatedSession session;
  final GirlsShopApp app;
  final HostedGroup? currentGroup;
  final VoidCallback? onGroupAppsChanged;
  final Future<void> Function(GirlsShopApp app) onHideCreator;

  @override
  State<GirlsShopDetailPage> createState() => _GirlsShopDetailPageState();
}

class _GirlsShopDetailPageState extends State<GirlsShopDetailPage> {
  late final HostedAppManagementApi _managementApi;
  HostedGroupApp? _installedCopy;
  bool _checkingInstallState = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managementApi = HostedAppManagementApi(baseUri: widget.api.baseUri);
    _loadInstallState();
  }

  @override
  void dispose() {
    _managementApi.close();
    super.dispose();
  }

  Future<void> _loadInstallState() async {
    final HostedGroup? group = widget.currentGroup;
    if (group == null) {
      if (mounted) setState(() => _checkingInstallState = false);
      return;
    }
    try {
      final List<HostedGroupApp> apps = await widget.api.listGroupApps(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
      );
      final List<HostedGroupApp> matches = apps
          .where(
            (HostedGroupApp candidate) =>
                candidate.sourceKind == 'upload' &&
                candidate.editable &&
                candidate.title == widget.app.title,
          )
          .toList(growable: false);
      if (matches.length > 1) {
        throw StateError(
          '同じ名前のアプリが複数あるため、ショップとの対応を判定できません。',
        );
      }
      if (!mounted) return;
      setState(() => _installedCopy = matches.isEmpty ? null : matches.single);
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _checkingInstallState = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launch() => _run(() async {
        final GirlsShopLaunchGrant grant = await widget.shopApi.createLaunch(
          accessToken: widget.session.accessToken,
          app: widget.app,
        );
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => HostedAppWebViewPage.session(
              title: widget.app.title,
              contentUri: grant.contentUri,
              runtimeToken: grant.runtimeToken,
              runtimeTransport: widget.api.runtimeClient,
            ),
          ),
        );
      });

  Future<void> _addToGroup() => _run(() async {
        final HostedGroup? group = widget.currentGroup;
        if (group == null) {
          throw StateError('追加先のグループが選ばれていません。');
        }
        final HostedGroupApp added = await widget.shopApi.addToGroup(
          accessToken: widget.session.accessToken,
          app: widget.app,
          groupId: group.groupId,
        );
        if (!mounted) return;
        setState(() => _installedCopy = added);
        widget.onGroupAppsChanged?.call();
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: InkWell(
              onTap: () {
                messenger.hideCurrentSnackBar();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => GirlsAppDetailPage(
                      api: widget.api,
                      session: widget.session,
                      appId: added.appId,
                    ),
                  ),
                );
              },
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '「${widget.app.title}」をマイアプリに追加したよ',
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        );
      });

  Future<void> _removeFromGroup() async {
    if (_busy) return;
    final HostedGroup? group = widget.currentGroup;
    final HostedGroupApp? installed = _installedCopy;
    if (group == null || installed == null) {
      setState(() => _error = '削除するアプリが見つかりません。');
      return;
    }
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('マイアプリから削除する？'),
            content: Text(
              '「${widget.app.title}」をマイアプリから削除します。'
              'この操作は取り消せません。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('削除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    await _run(() async {
      await _managementApi.deleteApp(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
        appId: installed.appId,
      );
      if (!mounted) return;
      setState(() => _installedCopy = null);
      widget.onGroupAppsChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${widget.app.title}」をマイアプリから削除したよ'),
        ),
      );
    });
  }

  Future<void> _report() async {
    if (_busy) return;
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFBF7),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'この作品を報告',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
              ),
            ),
            for (final String reason in const <String>[
              '不適切な表現・内容',
              '嫌がらせ・いじめ',
              '個人情報が含まれている',
              '危険な内容',
              'その他',
            ])
              ListTile(
                title: Text(reason),
                onTap: () => Navigator.of(sheetContext).pop(reason),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      await widget.shopApi.report(
        accessToken: widget.session.accessToken,
        app: widget.app,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('報告を受け付けたよ。')),
        );
      }
    });
  }

  Future<void> _block() => _run(() async {
        await widget.onHideCreator(widget.app);
        if (mounted) Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final GirlsShopApp app = widget.app;
    final bool embedded = GirlsScaffoldChromeScope.isEmbedded(context);
    final Color pageBackground = embedded ? Colors.transparent : _cream;
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text(
          'ショップ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        children: <Widget>[
          Center(
            child: _GirlsShopArtwork(
              app: app,
              size: 108,
              radius: 30,
              iconSize: 54,
              borderWidth: 3,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _shopDisplayTitle(app),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'by ${app.ownerDisplayName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9B7F91),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _launch,
            style: FilledButton.styleFrom(
              backgroundColor: _lavender,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('あそんでみる'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ||
                    _checkingInstallState ||
                    widget.currentGroup == null
                ? null
                : _installedCopy == null
                    ? _addToGroup
                    : _removeFromGroup,
            style: _installedCopy == null
                ? null
                : OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
            icon: Icon(
              _installedCopy == null
                  ? Icons.add_to_photos_rounded
                  : Icons.delete_outline_rounded,
            ),
            label: Text(
              widget.currentGroup == null
                  ? '追加するグループを選んでね'
                  : _checkingInstallState
                      ? '追加状況を確認中…'
                      : _installedCopy == null
                          ? 'マイアプリに追加'
                          : 'マイアプリから削除',
            ),
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: _busy ? null : _report,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('この作品を報告'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _block,
            icon: const Icon(Icons.block_outlined),
            label: const Text('このユーザーをブロック'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            _GirlsShopError(message: _error!),
          ],
        ],
      ),
    );
  }
}

class _GirlsShopArtwork extends StatelessWidget {
  const _GirlsShopArtwork({
    required this.app,
    required this.size,
    required this.radius,
    required this.iconSize,
    this.borderWidth = 1,
  });

  final GirlsShopApp app;
  final double size;
  final double radius;
  final double iconSize;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final String? assetPath = _shopArtworkAsset(app);
    if (assetPath != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          semanticLabel: _shopDisplayTitle(app),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF1E8FA),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: const Color(0xFFE2D2F1),
          width: borderWidth,
        ),
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: _lavender,
        size: iconSize,
      ),
    );
  }
}

class _GirlsShopError extends StatelessWidget {
  const _GirlsShopError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8EC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9B3C54),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
