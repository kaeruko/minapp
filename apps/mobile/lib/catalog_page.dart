import 'package:flutter/material.dart';

import 'api.dart';
import 'app_detail_page.dart';
import 'app_visual.dart';
import 'ui.dart';

const Color _brandBlue = Color(0xFF2563EB);
const Color _brandDark = Color(0xFF1E3A8A);
const Color _brandAccent = Color(0xFFF59E0B);
const Color _pageBackground = Color(0xFFF8FAFC);

enum _CatalogMenuAction { changeClassroom, logout }

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    required this.api,
    required this.session,
    required this.classroomName,
    required this.onChangeClassroom,
    required this.onLogout,
    super.key,
  });

  final MinAppApi api;
  final AuthenticatedSession session;
  final String classroomName;
  final Future<void> Function() onChangeClassroom;
  final VoidCallback onLogout;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final TextEditingController _searchController = TextEditingController();
  List<PublishedApp>? _apps;
  String? _error;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final List<PublishedApp> apps = await widget.api.listPublishedApps(
        widget.session.accessToken,
      );
      if (mounted) setState(() => _apps = apps);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        widget.onLogout();
        return;
      }
      setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openDetails(PublishedApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => AppDetailPage(
          api: widget.api,
          session: widget.session,
          app: app,
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  Future<void> _confirmChangeClassroom() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('教室を変更しますか？'),
        content: const Text('ログアウトして、この端末の教室設定と作品のWebViewデータを消します。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm-change-classroom'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('変更する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onChangeClassroom();
  }

  Future<void> _handleMenuAction(_CatalogMenuAction action) async {
    switch (action) {
      case _CatalogMenuAction.changeClassroom:
        await _confirmChangeClassroom();
      case _CatalogMenuAction.logout:
        widget.onLogout();
    }
  }

  List<PublishedApp> _filterApps(List<PublishedApp> apps) {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return apps;
    return apps.where((PublishedApp app) {
      return app.title.toLowerCase().contains(query) ||
          app.ownerLoginId.toLowerCase().contains(query) ||
          app.groupName.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  bool _isNew(PublishedApp app) {
    final DateTime now = DateTime.now().toUtc();
    if (app.reviewedAt.isAfter(now)) return false;
    return now.difference(app.reviewedAt).inDays <= 7;
  }

  @override
  Widget build(BuildContext context) {
    final List<PublishedApp>? apps = _apps;
    final List<PublishedApp>? filteredApps = apps == null ? null : _filterApps(apps);
    return Scaffold(
      backgroundColor: _pageBackground,
      floatingActionButton: FloatingActionButton(
        key: const Key('catalog-refresh'),
        tooltip: '更新',
        onPressed: _refreshing ? null : _loadApps,
        backgroundColor: _brandAccent,
        foregroundColor: Colors.white,
        elevation: 5,
        child: _refreshing
            ? const SizedBox(
                width: 23,
                height: 23,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.refresh_rounded, size: 29),
      ),
      body: Column(
        children: <Widget>[
          _CatalogHeader(
            classroomName: widget.classroomName,
            searchController: _searchController,
            onSearchChanged: () => setState(() {}),
            onMenuSelected: _handleMenuAction,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadApps,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
                children: <Widget>[
                  if (filteredApps != null)
                    Text(
                      'クラスの公開アプリ (${filteredApps.length})',
                      style: const TextStyle(
                        color: _brandDark,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFFBFDBFE),
                        decorationThickness: 2,
                        decorationStyle: TextDecorationStyle.solid,
                      ),
                    )
                  else
                    const Text(
                      'クラスの公開アプリ',
                      style: TextStyle(
                        color: _brandDark,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (_error != null) ...<Widget>[
                    _ErrorCard(message: _error!),
                    const SizedBox(height: 14),
                  ],
                  if (apps == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 54),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (apps.isEmpty)
                    const _EmptyCatalog()
                  else if (filteredApps!.isEmpty)
                    const _NoSearchResults()
                  else ...<Widget>[
                    for (final PublishedApp app in filteredApps) ...<Widget>[
                      _AppCard(
                        app: app,
                        isNew: _isNew(app),
                        onTap: () => _openDetails(app),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _searchController.text.trim().isEmpty
                          ? 'すべてのアプリを表示しました'
                          : '${filteredApps.length}件のアプリが見つかりました',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SafetyNote(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({
    required this.classroomName,
    required this.searchController,
    required this.onSearchChanged,
    required this.onMenuSelected,
  });

  final String classroomName;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final ValueChanged<_CatalogMenuAction> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _brandBlue,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          classroomName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFDBEAFE),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'みんアプ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_CatalogMenuAction>(
                    key: const Key('catalog-menu'),
                    tooltip: 'メニュー',
                    onSelected: onMenuSelected,
                    icon: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4F7DF0),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.menu_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    itemBuilder: (BuildContext context) => const <PopupMenuEntry<_CatalogMenuAction>>[
                      PopupMenuItem<_CatalogMenuAction>(
                        value: _CatalogMenuAction.changeClassroom,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.swap_horiz_rounded),
                          title: Text('教室を変更'),
                        ),
                      ),
                      PopupMenuItem<_CatalogMenuAction>(
                        value: _CatalogMenuAction.logout,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.logout_rounded),
                          title: Text('ログアウト'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('catalog-search'),
                controller: searchController,
                onChanged: (_) => onSearchChanged(),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'アプリを探す…',
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '検索をクリア',
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                      color: Color(0xFFBFDBFE),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.isNew, required this.onTap});

  final PublishedApp app;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppVisual visual = appVisualFor(app);
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: const Color(0x14000000),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: visual.backgroundColor,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: visual.borderColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  visual.icon,
                  size: 31,
                  color: visual.foregroundColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.account_circle_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            app.ownerLoginId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isNew) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Color(0xFF15803D),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              const Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.web_asset_off_outlined, size: 40, color: Color(0xFF64748B)),
          SizedBox(height: 12),
          Text(
            'まだ承認済みのアプリがありません。',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Webポータルから公開申請して、先生に承認してもらってね。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: 44, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text(
            '一致するアプリがありません',
            style: TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, color: _brandBlue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '作品にはログイン情報・カメラ・位置情報・マイクを渡しません。外部サイトへの移動も拒否します。',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
