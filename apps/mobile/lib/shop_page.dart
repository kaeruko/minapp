import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'app_webview.dart';
import 'shop_api.dart';
import 'ugc_safety.dart';
import 'ui.dart';

const Color _shopBlue = Color(0xFF2563EB);
const Color _shopDark = Color(0xFF1E3A8A);
const Color _shopBackground = Color(0xFFF8FAFC);

class ShopPage extends StatefulWidget {
  const ShopPage({
    required this.api,
    required this.session,
    required this.creatorSafetyStore,
    required this.onLogout,
    super.key,
  });

  final ShopApiClient api;
  final AuthenticatedSession session;
  final CreatorSafetyStore creatorSafetyStore;
  final VoidCallback onLogout;

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final TextEditingController _searchController = TextEditingController();
  List<ShopApp>? _apps;
  Set<String> _hiddenCreators = <String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
          await widget.creatorSafetyStore.loadHiddenCreatorUserIds();
      final List<ShopApp> apps = await widget.api.listApps(
        widget.session.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _hiddenCreators = hidden;
        _apps = apps;
      });
    } catch (error) {
      if (!mounted) return;
      if (_handleUnauthorized(error)) return;
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _handleUnauthorized(Object error) {
    if (error is ApiException && error.statusCode == 401) {
      widget.onLogout();
      return true;
    }
    return false;
  }

  List<ShopApp> _visibleApps() {
    final List<ShopApp> apps = _apps ?? const <ShopApp>[];
    final String query = _searchController.text.trim().toLowerCase();
    return apps.where((ShopApp app) {
      if (_hiddenCreators.contains(app.ownerUserId)) return false;
      if (query.isEmpty) return true;
      return app.title.toLowerCase().contains(query) ||
          app.ownerDisplayName.toLowerCase().contains(query) ||
          (app.description?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  Future<void> _hideCreator(ShopApp app) async {
    await widget.creatorSafetyStore.hideCreator(app.ownerUserId);
    if (!mounted) return;
    setState(() {
      _hiddenCreators = <String>{..._hiddenCreators, app.ownerUserId};
    });
  }

  Future<void> _open(ShopApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ShopAppDetailPage(
          api: widget.api,
          session: widget.session,
          app: app,
          onHideCreator: _hideCreator,
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ShopApp> visible = _visibleApps();
    return Scaffold(
      backgroundColor: _shopBackground,
      appBar: AppBar(
        title: const Text(
          'みんアプショップ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '更新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: <Widget>[
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '作品名・作者名で検索',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (_apps == null && _loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 54),
                child: Center(
                  child: Text(
                    'ショップに表示できる作品はまだありません。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              for (final ShopApp app in visible) ...<Widget>[
                _ShopCard(app: app, onTap: () => _open(app)),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.app, required this.onTap});

  final ShopApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.widgets_rounded,
                  color: _shopBlue,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _shopDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'by ${app.ownerDisplayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopAppDetailPage extends StatefulWidget {
  const ShopAppDetailPage({
    required this.api,
    required this.session,
    required this.app,
    required this.onHideCreator,
    required this.onLogout,
    super.key,
  });

  final ShopApiClient api;
  final AuthenticatedSession session;
  final ShopApp app;
  final Future<void> Function(ShopApp app) onHideCreator;
  final VoidCallback onLogout;

  @override
  State<ShopAppDetailPage> createState() => _ShopAppDetailPageState();
}

class _ShopAppDetailPageState extends State<ShopAppDetailPage> {
  bool _busy = false;
  String? _error;

  bool _handleUnauthorized(Object error) {
    if (error is ApiException && error.statusCode == 401) {
      widget.onLogout();
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
      return true;
    }
    return false;
  }

  Future<void> _launch() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
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
    } catch (error) {
      if (!mounted) return;
      if (_handleUnauthorized(error)) return;
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ShopDownloadGrant grant = await widget.api.createDownload(
        accessToken: widget.session.accessToken,
        app: widget.app,
      );
      final bool opened = await launchUrl(
        grant.url,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('ZIP download URL could not be opened.');
      }
    } catch (error) {
      if (!mounted) return;
      if (_handleUnauthorized(error)) return;
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    if (_busy) return;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('この作品を報告'),
        children: <Widget>[
          for (final String reason in const <String>[
            '不適切な表現・内容',
            '嫌がらせ・いじめ',
            '個人情報が含まれている',
            '危険な内容',
            'その他',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(reason),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(reason),
              ),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.report(
        accessToken: widget.session.accessToken,
        app: widget.app,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('報告を受け付けました。')),
      );
    } catch (error) {
      if (!mounted) return;
      if (_handleUnauthorized(error)) return;
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blockCreator() async {
    if (_busy) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('このユーザーをブロック'),
        content: Text('「${widget.app.ownerDisplayName}」さんの作品をこの端末で非表示にしますか？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ブロックする'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onHideCreator(widget.app);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShopApp app = widget.app;
    return Scaffold(
      appBar: AppBar(title: const Text('みんアプショップ')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          const Icon(Icons.widgets_rounded, size: 78, color: _shopBlue),
          const SizedBox(height: 20),
          Text(
            app.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _shopDark,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '作成者：${app.ownerDisplayName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (app.description != null) ...<Widget>[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(app.description!),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _launch,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('あそんでみる'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('ZIPをもらう'),
          ),
          const SizedBox(height: 22),
          TextButton.icon(
            onPressed: _busy ? null : _report,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('この作品を報告'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _blockCreator,
            icon: const Icon(Icons.block_outlined),
            label: const Text('このユーザーをブロック'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
