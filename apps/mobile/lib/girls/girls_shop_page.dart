import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../app_webview.dart';
import '../shop_api.dart';
import '../ugc_safety.dart';
import '../ui.dart';
import 'girls_scaffold.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const Color _pink = Color(0xFFE987A8);
const Color _cream = Color(0xFFFFFAF0);

class GirlsShopPage extends StatefulWidget {
  const GirlsShopPage({
    required this.baseUri,
    required this.session,
    super.key,
  });

  final Uri baseUri;
  final AuthenticatedSession session;

  @override
  State<GirlsShopPage> createState() => _GirlsShopPageState();
}

class _GirlsShopPageState extends State<GirlsShopPage> {
  late final ShopApiClient _api;
  final CreatorSafetyStore _safetyStore = SharedPreferencesCreatorSafetyStore();
  final TextEditingController _searchController = TextEditingController();
  List<ShopApp>? _apps;
  Set<String> _hiddenCreators = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ShopApiClient(baseUri: widget.baseUri);
    _load();
  }

  @override
  void dispose() {
    _api.close();
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
      final Set<String> hidden = await _safetyStore.loadHiddenCreatorUserIds();
      final List<ShopApp> apps = await _api.listApps(widget.session.accessToken);
      if (!mounted) return;
      setState(() {
        _hiddenCreators = hidden;
        _apps = apps;
      });
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ShopApp> _visibleApps() {
    final String query = _searchController.text.trim().toLowerCase();
    return (_apps ?? const <ShopApp>[]).where((ShopApp app) {
      if (_hiddenCreators.contains(app.ownerUserId)) return false;
      if (query.isEmpty) return true;
      return app.title.toLowerCase().contains(query) ||
          app.ownerDisplayName.toLowerCase().contains(query) ||
          (app.description?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  Future<void> _hideCreator(ShopApp app) async {
    await _safetyStore.hideCreator(app.ownerUserId);
    if (!mounted) return;
    setState(() {
      _hiddenCreators = <String>{..._hiddenCreators, app.ownerUserId};
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<ShopApp> apps = _visibleApps();
    return GirlsScaffold(
      title: 'ショップ ♡',
      actions: <Widget>[
        IconButton(
          tooltip: '更新',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9DDE8),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.storefront_rounded, color: _pink, size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'みんなの作品を見つけて、遊んだりZIPをもらったりできるよ♡',
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
                    style: TextStyle(color: Color(0xFF8C7893), fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              for (final ShopApp app in apps) ...<Widget>[
                _GirlsShopCard(
                  app: app,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => GirlsShopDetailPage(
                          api: _api,
                          session: widget.session,
                          app: app,
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

  final ShopApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1E8FA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2D2F1)),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: _lavender, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.title,
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
                      style: const TextStyle(color: Color(0xFF9B7F91), fontWeight: FontWeight.w700),
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
    required this.session,
    required this.app,
    required this.onHideCreator,
    super.key,
  });

  final ShopApiClient api;
  final AuthenticatedSession session;
  final ShopApp app;
  final Future<void> Function(ShopApp app) onHideCreator;

  @override
  State<GirlsShopDetailPage> createState() => _GirlsShopDetailPageState();
}

class _GirlsShopDetailPageState extends State<GirlsShopDetailPage> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launch() => _run(() async {
        final ShopLaunchGrant grant = await widget.api.createLaunch(
          accessToken: widget.session.accessToken,
          app: widget.app,
        );
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => AppWebViewPage(
              title: widget.app.title,
              launchUrl: grant.url,
            ),
          ),
        );
      });

  Future<void> _download() => _run(() async {
        final ShopDownloadGrant grant = await widget.api.createDownload(
          accessToken: widget.session.accessToken,
          app: widget.app,
        );
        final bool opened = await launchUrl(grant.url, mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('ZIP download URL could not be opened.');
      });

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
              child: Text('この作品を報告', style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
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
      await widget.api.report(
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
    final ShopApp app = widget.app;
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        title: const Text('ショップ ♡', style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        children: <Widget>[
          Center(
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: const Color(0xFFF1E8FA),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFE2D2F1), width: 3),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: _lavender, size: 54),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            app.title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'by ${app.ownerDisplayName}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9B7F91), fontWeight: FontWeight.w700),
          ),
          if (app.description != null) ...<Widget>[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text(app.description!, style: const TextStyle(color: _ink, height: 1.55)),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _launch,
            style: FilledButton.styleFrom(backgroundColor: _lavender, padding: const EdgeInsets.symmetric(vertical: 15)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('あそんでみる♡'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('ZIPをもらう'),
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
      child: Text(message, style: const TextStyle(color: Color(0xFF9B3C54), fontWeight: FontWeight.w700)),
    );
  }
}
