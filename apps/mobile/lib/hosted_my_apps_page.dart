import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'hosted_app.dart' show hostedMessageFor;
import 'hosted_app_management_api.dart';

class HostedMyAppsPage extends StatefulWidget {
  const HostedMyAppsPage({
    required this.baseUri,
    required this.session,
    super.key,
  });

  final Uri baseUri;
  final AuthenticatedSession session;

  @override
  State<HostedMyAppsPage> createState() => _HostedMyAppsPageState();
}

class _HostedMyAppsPageState extends State<HostedMyAppsPage> {
  late final HostedAppManagementApi _api;
  List<ManagedHostedApp>? _apps;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = HostedAppManagementApi(baseUri: widget.baseUri);
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<ManagedHostedApp> apps =
          await _api.listApps(widget.session.accessToken);
      if (mounted) setState(() => _apps = apps);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(ManagedHostedApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedManagedAppDetailPage(
          baseUri: widget.baseUri,
          session: widget.session,
          appId: app.app.appId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<ManagedHostedApp>? apps = _apps;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自分のアプリ'),
        actions: <Widget>[
          IconButton(
            key: const Key('hosted-my-apps-refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              const Text('自分が作成・管理できるHostedアプリです。'),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                _HostedManagementError(message: _error!),
              ],
              const SizedBox(height: 16),
              if (apps == null)
                const Center(child: CircularProgressIndicator())
              else if (apps.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('まだ管理できるアプリがありません。'),
                  ),
                )
              else
                ...apps.map(
                  (ManagedHostedApp app) => Card(
                    child: ListTile(
                      key: Key('hosted-managed-app-${app.app.appId}'),
                      leading: const Icon(Icons.apps_rounded),
                      title: Text(app.app.title),
                      subtitle: Text(
                        '${app.groupName ?? app.app.groupId} ・ ${_status(app)} ・ '
                        '${app.stats.uniqueUsers}人 / ${app.stats.totalPlays}回',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : () => _open(app),
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

class HostedManagedAppDetailPage extends StatefulWidget {
  const HostedManagedAppDetailPage({
    required this.baseUri,
    required this.session,
    required this.appId,
    super.key,
  });

  final Uri baseUri;
  final AuthenticatedSession session;
  final String appId;

  @override
  State<HostedManagedAppDetailPage> createState() =>
      _HostedManagedAppDetailPageState();
}

class _HostedManagedAppDetailPageState
    extends State<HostedManagedAppDetailPage> {
  late final HostedAppManagementApi _api;
  ManagedHostedAppDetail? _detail;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = HostedAppManagementApi(baseUri: widget.baseUri);
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ManagedHostedAppDetail detail = await _api.getApp(
        accessToken: widget.session.accessToken,
        appId: widget.appId,
      );
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleHidden() async {
    final ManagedHostedAppDetail? detail = _detail;
    if (detail == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.setHidden(
        accessToken: widget.session.accessToken,
        appId: detail.summary.app.appId,
        hidden: !detail.summary.isHidden,
      );
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final ManagedHostedAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) {
      setState(() => _error = '公開するsource revisionを確認できません。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.publish(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
        revision: revision,
      );
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _updateSource() async {
    final ManagedHostedAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) {
      setState(() => _error = '更新元のsource revisionを確認できません。');
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
      if (mounted) setState(() => _error = '選択したZIPを読み込めませんでした: $error');
      return;
    }
    if (bytes.isEmpty || bytes.length > maxHostedZipUploadBytes) {
      setState(() => _error = 'ZIPは1byte以上2MB以下にしてください。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.updateSource(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
        expectedRevision: revision,
        zipBytes: bytes,
      );
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = hostedMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ManagedHostedAppDetail? detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.summary.app.title ?? 'アプリ詳細'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              _HostedManagementError(message: _error!),
              const SizedBox(height: 12),
            ],
            if (detail == null)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        detail.summary.app.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('状態: ${_status(detail.summary)}'),
                      Text('グループ: ${detail.summary.groupName ?? detail.summary.app.groupId}'),
                      Text('公開version: ${detail.summary.app.publishedVersion ?? '-'}'),
                      Text('source revision: ${detail.summary.sourceRevision ?? '-'}'),
                      Text('利用人数: ${detail.summary.stats.uniqueUsers}人'),
                      Text('起動回数: ${detail.summary.stats.totalPlays}回'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('hosted-managed-update-source'),
                onPressed: _busy || detail.summary.sourceRevision == null
                    ? null
                    : _updateSource,
                icon: const Icon(Icons.folder_zip_rounded),
                label: const Text('新しいZIPで更新'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('hosted-managed-publish'),
                onPressed: _busy || detail.summary.sourceRevision == null
                    ? null
                    : _publish,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('最新版を公開'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('hosted-managed-visibility'),
                onPressed: _busy ? null : _toggleHidden,
                icon: Icon(
                  detail.summary.isHidden
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                label: Text(
                  detail.summary.isHidden ? '再公開する' : '非表示にする',
                ),
              ),
              const SizedBox(height: 24),
              Text('source履歴', style: Theme.of(context).textTheme.titleMedium),
              if (detail.sourceHistory.isEmpty)
                const Text('まだ更新履歴がありません。')
              else
                ...detail.sourceHistory.map(
                  (HostedSourceHistoryItem item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_rounded),
                    title: Text('revision ${item.revision}'),
                    subtitle: Text(_formatDate(item.createdAt)),
                  ),
                ),
              const SizedBox(height: 12),
              Text('公開履歴', style: Theme.of(context).textTheme.titleMedium),
              if (detail.publishedHistory.isEmpty)
                const Text('まだ公開履歴がありません。')
              else
                ...detail.publishedHistory.map(
                  (HostedPublishedHistoryItem item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.public_rounded),
                    title: Text(
                      'v${item.version} / revision ${item.sourceRevision}',
                    ),
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

String _status(ManagedHostedApp app) {
  if (app.isHidden) return '非表示';
  if (app.app.isPublished) return '公開中';
  return '下書き';
}

String _formatDate(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _HostedManagementError extends StatelessWidget {
  const _HostedManagementError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
