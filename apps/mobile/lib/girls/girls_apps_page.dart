import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_app_management_api.dart';
import 'girls_footer_nav.dart';
import 'girls_zip_upload_page.dart';
import 'hosted_girls_api.dart';
import 'hosted_girls_upload_api.dart';

const Color _cream = Color(0xFFFFFAF0);
const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const Color _pink = Color(0xFFF9DDE8);
const Color _mint = Color(0xFFDDF4E4);

class GirlsAppsPage extends StatefulWidget {
  const GirlsAppsPage({
    required this.api,
    required this.session,
    this.onHome,
    this.onGroups,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback? onHome;
  final VoidCallback? onGroups;

  @override
  State<GirlsAppsPage> createState() => _GirlsAppsPageState();
}

class _GirlsAppsPageState extends State<GirlsAppsPage> {
  late final GirlsAppManagementApi _managementApi;
  List<ManagedGirlsApp>? _apps;
  List<HostedGroup>? _ownerGroups;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managementApi = GirlsAppManagementApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void dispose() {
    _managementApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        widget.session.accessToken,
      );
      final List<ManagedGirlsApp> apps = await _managementApi.listApps(
        widget.session.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _ownerGroups = groups.where((HostedGroup group) => group.isOwner).toList(growable: false);
        _apps = apps;
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openZipUpload() async {
    final List<HostedGroup>? ownerGroups = _ownerGroups;
    if (ownerGroups == null) return;
    if (ownerGroups.isEmpty) {
      setState(() => _error = 'ZIPを追加するには、自分がオーナーのグループが必要です。');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsZipUploadPage(
          api: widget.api,
          session: widget.session,
          ownerGroups: ownerGroups,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openDetail(ManagedGirlsApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GirlsAppDetailPage(
          api: widget.api,
          session: widget.session,
          appId: app.app.appId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<ManagedGirlsApp>? apps = _apps;
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _ink,
        automaticallyImplyLeading: false,
        title: const Text('マイアプリ', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: <Widget>[
          IconButton(
            tooltip: '更新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: <Widget>[
              FilledButton.icon(
                key: const Key('girls-my-apps-upload'),
                onPressed: _busy ? null : _openZipUpload,
                style: FilledButton.styleFrom(
                  backgroundColor: _lavender,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: const Icon(Icons.folder_zip_rounded),
                label: const Text('ZIPからアプリを追加'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorCard(message: _error!),
              ],
              const SizedBox(height: 22),
              const Text(
                'あなたのアプリ',
                style: TextStyle(
                  color: _ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (apps == null)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (apps.isEmpty)
                const _EmptyApps()
              else
                ...apps.map(
                  (ManagedGirlsApp app) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ManagedAppCard(
                      app: app,
                      onTap: _busy ? null : () => _openDetail(app),
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
          selectedTab: GirlsFooterTab.apps,
          enabledTabs: <GirlsFooterTab>{
            if (widget.onHome != null) GirlsFooterTab.home,
            if (widget.onGroups != null) GirlsFooterTab.groups,
            GirlsFooterTab.apps,
            GirlsFooterTab.more,
          },
          onSelected: (GirlsFooterTab tab) {
            switch (tab) {
              case GirlsFooterTab.home:
                widget.onHome?.call();
              case GirlsFooterTab.groups:
                widget.onGroups?.call();
              case GirlsFooterTab.apps:
                break;
              case GirlsFooterTab.shop:
                break;
              case GirlsFooterTab.more:
                _showMoreMenu(context);
            }
          },
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFBF7),
      builder: (BuildContext context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.apps_rounded, color: _lavender),
          title: const Text('マイアプリ'),
          subtitle: const Text('追加したアプリを管理'),
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class GirlsAppDetailPage extends StatefulWidget {
  const GirlsAppDetailPage({
    required this.api,
    required this.session,
    required this.appId,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final String appId;

  @override
  State<GirlsAppDetailPage> createState() => _GirlsAppDetailPageState();
}

class _GirlsAppDetailPageState extends State<GirlsAppDetailPage> {
  late final GirlsAppManagementApi _managementApi;
  ManagedGirlsAppDetail? _detail;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managementApi = GirlsAppManagementApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void dispose() {
    _managementApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ManagedGirlsAppDetail detail = await _managementApi.getApp(
        accessToken: widget.session.accessToken,
        appId: widget.appId,
      );
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateZip() async {
    final ManagedGirlsAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) {
      setState(() => _error = '更新元のrevisionを確認できません。');
      return;
    }
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (file == null || !mounted) return;
    if (file.extension?.toLowerCase() != 'zip') {
      setState(() => _error = '拡張子 .zip のファイルを選んでください。');
      return;
    }
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      if (mounted) setState(() => _error = 'ZIPを読み込めませんでした: $error');
      return;
    }
    if (bytes.isEmpty || bytes.length > maxGirlsZipUploadBytes) {
      setState(() => _error = 'ZIPは1byte以上2MB以下にしてください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.updateSource(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
        expectedRevision: revision,
        zipBytes: bytes,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final ManagedGirlsAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.publish(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
        revision: revision,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleHidden() async {
    final ManagedGirlsAppDetail? detail = _detail;
    if (detail == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.setHidden(
        accessToken: widget.session.accessToken,
        appId: detail.summary.app.appId,
        hidden: !detail.summary.isHidden,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ManagedGirlsAppDetail? detail = _detail;
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _ink,
        title: Text(detail?.summary.app.title ?? 'アプリ詳細'),
        actions: <Widget>[
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              _ErrorCard(message: _error!),
              const SizedBox(height: 12),
            ],
            if (detail == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              _AppSummary(detail: detail),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _updateZip,
                      icon: const Icon(Icons.folder_zip_rounded),
                      label: const Text('新しいZIPで更新'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || detail.summary.sourceRevision == null ? null : _publish,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('最新版を公開'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _toggleHidden,
                icon: Icon(detail.summary.isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                label: Text(detail.summary.isHidden ? '再公開する' : '非表示にする'),
              ),
              const SizedBox(height: 24),
              const Text('バージョン履歴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (detail.sourceHistory.isEmpty)
                const Text('まだ更新履歴がありません。')
              else
                ...detail.sourceHistory.map(
                  (GirlsSourceHistoryItem item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_rounded, color: _lavender),
                    title: Text('revision ${item.revision}'),
                    subtitle: Text(_formatDate(item.createdAt)),
                  ),
                ),
              const SizedBox(height: 14),
              const Text('公開履歴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (detail.publishedHistory.isEmpty)
                const Text('まだ公開履歴がありません。')
              else
                ...detail.publishedHistory.map(
                  (GirlsPublishedHistoryItem item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.public_rounded, color: _lavender),
                    title: Text('v${item.version}  /  revision ${item.sourceRevision}'),
                    subtitle: Text(_formatDate(item.publishedAt)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppSummary extends StatelessWidget {
  const _AppSummary({required this.detail});

  final ManagedGirlsAppDetail detail;

  @override
  Widget build(BuildContext context) {
    final ManagedGirlsApp app = detail.summary;
    final String status = app.isHidden
        ? '非公開'
        : app.app.isPublished
            ? '公開中'
            : '下書き';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF0D6DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(app.app.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 4),
          Text(status, style: const TextStyle(color: _lavender, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _Stat(label: '遊ばれた回数', value: '${app.stats.totalPlays}回')),
              Expanded(child: _Stat(label: '遊んだ人数', value: '${app.stats.uniqueUsers}人')),
              Expanded(child: _Stat(label: '今月', value: '${app.stats.monthlyPlays}回')),
            ],
          ),
          const SizedBox(height: 14),
          Text('公開バージョン: ${app.app.publishedVersion ?? '-'}'),
          Text('最新revision: ${app.sourceRevision ?? '-'}'),
          Text('最終更新: ${app.sourceUpdatedAt == null ? '-' : _formatDate(app.sourceUpdatedAt!)}'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _lavender)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: _ink), textAlign: TextAlign.center),
      ],
    );
  }
}

class _ManagedAppCard extends StatelessWidget {
  const _ManagedAppCard({required this.app, required this.onTap});
  final ManagedGirlsApp app;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String status = app.isHidden
        ? '非公開'
        : app.app.isPublished
            ? '公開中'
            : '下書き';
    return Material(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: app.isHidden ? const Color(0xFFE9E2E0) : _pink,
                foregroundColor: _lavender,
                child: const Icon(Icons.apps_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(app.app.title, style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                    const SizedBox(height: 3),
                    Text('$status  ・  ${app.stats.uniqueUsers}人 / ${app.stats.totalPlays}回'),
                    if (app.groupName != null)
                      Text(app.groupName!, style: const TextStyle(fontSize: 11, color: Color(0xFF8F7A74))),
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

class _EmptyApps extends StatelessWidget {
  const _EmptyApps();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(20)),
      child: const Column(
        children: <Widget>[
          Icon(Icons.favorite_outline_rounded, color: _lavender, size: 34),
          SizedBox(height: 8),
          Text('まだマイアプリがないよ。\nZIPから最初のアプリを追加してみよう。', textAlign: TextAlign.center),
        ],
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
        color: const Color(0xFFFFECEF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB8C5)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF9E3348))),
    );
  }
}

String _formatDate(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
