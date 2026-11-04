import 'package:flutter/material.dart';

import '../api.dart';
import '../hosted_app_webview.dart';
import '../hosted_consumer_api.dart';
import '../hosted_consumer_errors.dart';
import '../hosted_runtime_bridge.dart';
import '../hosted_shop_api.dart';
import '../hosted_shop_guest_preview_transport.dart';
import 'kobo_components.dart';
import 'kobo_theme.dart';

class KoboShopPage extends StatefulWidget {
  const KoboShopPage({
    required this.api,
    required this.session,
    required this.onNavigationSelected,
    super.key,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession? session;
  final ValueChanged<KoboNavigationItem> onNavigationSelected;

  @override
  State<KoboShopPage> createState() => _KoboShopPageState();
}

class _KoboShopPageState extends State<KoboShopPage> {
  late final HostedShopApi _shopApi;
  final TextEditingController _searchController = TextEditingController();
  List<HostedShopApp>? _apps;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shopApi = HostedShopApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
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
      final List<HostedShopApp> apps =
          await _shopApi.listApps(widget.session?.accessToken);
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<HostedShopApp> _visibleApps() {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _apps ?? const <HostedShopApp>[];
    return (_apps ?? const <HostedShopApp>[])
        .where(
          (HostedShopApp app) =>
              app.title.toLowerCase().contains(query) ||
              app.ownerDisplayName.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _play(HostedShopApp app) async {
    final AuthenticatedSession? session = widget.session;
    final HostedGuestPreviewRuntimeTransport? guestPreview =
        session == null ? HostedGuestPreviewRuntimeTransport() : null;
    try {
      final Uri contentUri;
      final String runtimeToken;
      final HostedRuntimeTransport runtimeTransport;
      if (guestPreview != null) {
        contentUri = _shopApi.guestPreviewUri(app);
        runtimeToken = guestPreview.runtimeToken;
        runtimeTransport = guestPreview;
      } else {
        final HostedShopLaunchGrant grant = await _shopApi.createLaunch(
          accessToken: session!.accessToken,
          app: app,
        );
        contentUri = grant.contentUri;
        runtimeToken = grant.runtimeToken;
        runtimeTransport = widget.api.runtimeClient;
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.session(
            title: app.title,
            contentUri: contentUri,
            runtimeToken: runtimeToken,
            runtimeTransport: runtimeTransport,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hostedConsumerMessageFor(error))),
        );
      }
    } finally {
      guestPreview?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedShopApp> apps = _visibleApps();
    return Scaffold(
      appBar: AppBar(
        title: const Text('みんなのアプリ'),
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
          padding: const EdgeInsets.fromLTRB(
            KoboSpacing.md,
            KoboSpacing.md,
            KoboSpacing.md,
            KoboSpacing.lg,
          ),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(KoboSpacing.md),
              decoration: BoxDecoration(
                color: KoboColors.paper,
                borderRadius: BorderRadius.circular(KoboRadii.card),
                border: Border.all(color: KoboColors.divider),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.storefront_outlined,
                    color: KoboColors.mustard,
                    size: 38,
                  ),
                  SizedBox(width: KoboSpacing.sm),
                  Expanded(
                    child: Text(
                      '気になる道具は、登録前でもその場で試せます。',
                      style: KoboTextStyles.body,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KoboSpacing.md),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '道具名・作者名で探す',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: KoboSpacing.sm),
              Container(
                padding: const EdgeInsets.all(KoboSpacing.sm),
                decoration: BoxDecoration(
                  color: KoboColors.error.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(KoboRadii.input),
                  border: Border.all(color: KoboColors.error),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: KoboColors.error),
                ),
              ),
            ],
            const SizedBox(height: KoboSpacing.md),
            if (_apps == null && _loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (apps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.inventory_2_outlined,
                      color: KoboColors.brown,
                      size: 42,
                    ),
                    SizedBox(height: KoboSpacing.sm),
                    Text('公開中の道具はまだありません。'),
                  ],
                ),
              )
            else
              for (final HostedShopApp app in apps) ...<Widget>[
                _KoboShopCard(
                  app: app,
                  thumbnailUri: _shopApi.thumbnailUri(app),
                  onPlay: () => _play(app),
                ),
                const SizedBox(height: KoboSpacing.sm),
              ],
          ],
        ),
      ),
      bottomNavigationBar: KoboBottomNavigation(
        selectedItem: KoboNavigationItem.community,
        onSelected: widget.onNavigationSelected,
      ),
    );
  }
}

class _KoboShopCard extends StatelessWidget {
  const _KoboShopCard({
    required this.app,
    required this.thumbnailUri,
    required this.onPlay,
  });

  final HostedShopApp app;
  final Uri? thumbnailUri;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KoboSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: KoboColors.paperLight,
                borderRadius: BorderRadius.circular(KoboRadii.input),
                border: Border.all(color: KoboColors.divider),
              ),
              child: thumbnailUri == null
                  ? const Icon(
                      Icons.handyman_outlined,
                      color: KoboColors.navy,
                      size: 30,
                    )
                  : Image.network(
                      thumbnailUri.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.handyman_outlined,
                        color: KoboColors.navy,
                        size: 30,
                      ),
                    ),
            ),
            const SizedBox(width: KoboSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(app.title, style: KoboTextStyles.cardTitle),
                  const SizedBox(height: KoboSpacing.xxs),
                  Text(
                    '作り手：${app.ownerDisplayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KoboTextStyles.secondary,
                  ),
                  const SizedBox(height: KoboSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      key: Key('kobo-shop-play-${app.appId}'),
                      onPressed: onPlay,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: KoboColors.navy,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('遊んでみる'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
