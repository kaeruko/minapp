import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../hosted_app_webview.dart';
import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_app_management_api.dart';
import 'girls_app_preview_api.dart';
import 'hosted_girls_api.dart';

const Color _cream = Color(0xFFFFFAF0);
const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);

class GirlsGroupAppManagementPage extends StatefulWidget {
  const GirlsGroupAppManagementPage({
    required this.api,
    required this.session,
    required this.group,
    required this.appId,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroup group;
  final String appId;

  @override
  State<GirlsGroupAppManagementPage> createState() =>
      _GirlsGroupAppManagementPageState();
}

class _GirlsGroupAppManagementPageState
    extends State<GirlsGroupAppManagementPage> {
  late final GirlsAppManagementApi _managementApi;
  late final GirlsAppPreviewApi _previewApi;
  HostedGroupApp? _app;
  String? _authorLabel;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.group.isOwner) {
      throw ArgumentError(
        'GirlsGroupAppManagementPage requires the current group owner role.',
      );
    }
    _managementApi = GirlsAppManagementApi(baseUri: widget.api.baseUri);
    _previewApi = GirlsAppPreviewApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void dispose() {
    _managementApi.close();
    _previewApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroupApp> apps = await widget.api.listGroupApps(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      final List<HostedGroupApp> matches = apps
          .where((HostedGroupApp app) => app.appId == widget.appId)
          .toList(growable: false);
      if (matches.length != 1) {
        throw StateError(
          'Group app management expected exactly one app, found ${matches.length}.',
        );
      }
      final HostedGroupApp app = matches.single;
      if (!app.editable || app.sourceRevision == null) {
        throw StateError('Only editable apps can be managed from this page.');
      }

      final List<HostedMember> members = await widget.api.listMembers(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
      );
      final List<HostedMember> authors = members
          .where((HostedMember member) => member.userId == app.ownerUserId)
          .toList(growable: false);
      if (authors.length > 1) {
        throw StateError('Group member list contains duplicate app owner IDs.');
      }
      final String authorLabel = authors.isEmpty
          ? '退出済みユーザー (${app.ownerUserId.substring(0, 8)}…)'
          : authors.single.loginId;
      if (!mounted) return;
      setState(() {
        _app = app;
        _authorLabel = authorLabel;
      });
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  HostedGroupApp _requireEditableApp() {
    final HostedGroupApp? app = _app;
    if (app == null || !app.editable || app.sourceRevision == null) {
      throw StateError('Editable group app metadata is not loaded.');
    }
    return app;
  }

  Future<void> _downloadZip() async {
    final HostedGroupApp app = _requireEditableApp();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedSourceDownload download = await _managementApi.downloadSource(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (download.revision != app.sourceRevision) {
        throw StateError(
          'Downloaded source revision ${download.revision} does not match the loaded revision ${app.sourceRevision}.',
        );
      }
      final String? savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'ZIPを保存',
        fileName: 'minapp-${app.appId}.zip',
        bytes: download.bytes,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ZIPを保存しました。')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateZip() async {
    final HostedGroupApp app = _requireEditableApp();
    final int revision = app.sourceRevision!;
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
        groupId: widget.group.groupId,
        appId: app.appId,
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
    final HostedGroupApp app = _requireEditableApp();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.publish(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
        revision: app.sourceRevision!,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewDraft() async {
    final HostedGroupApp app = _requireEditableApp();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GirlsAppTestSession launch =
          await _previewApi.createGroupDraftPreview(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (launch.sourceRevision != app.sourceRevision) {
        throw StateError(
          'Preview revision ${launch.sourceRevision} does not match the loaded revision ${app.sourceRevision}.',
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.session(
            title: '${app.title}（管理プレビュー）',
            contentUri: launch.contentUri,
            runtimeToken: launch.runtimeToken,
            runtimeTransport: widget.api.runtimeClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _setHidden(bool hidden) async {
    final HostedGroupApp app = _requireEditableApp();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.setGroupHidden(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
        hidden: hidden,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hidden ? 'アプリを非表示にしました。' : 'アプリを再表示しました。'),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final HostedGroupApp app = _requireEditableApp();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('このアプリを削除する？'),
        content: Text('「${app.title}」をグループから削除します。この操作は取り消せません。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _managementApi.deleteApp(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HostedGroupApp? app = _app;
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _ink,
        title: Text(app?.title ?? 'グループアプリ管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '更新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              _AdminError(message: _error!),
              const SizedBox(height: 12),
            ],
            if (app == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .88),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('作者: ${_authorLabel ?? '確認中…'}'),
                    Text('作者ID: ${app.ownerUserId}'),
                    Text('最新revision: ${app.sourceRevision}'),
                    Text('公開バージョン: ${app.publishedVersion ?? '-'}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                key: const Key('girls-group-admin-preview'),
                onPressed: _busy ? null : _previewDraft,
                icon: const Icon(Icons.preview_rounded),
                label: const Text('下書きをプレビュー'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('girls-group-admin-download'),
                onPressed: _busy ? null : _downloadZip,
                icon: const Icon(Icons.download_rounded),
                label: const Text('現在のZIPを保存'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('girls-group-admin-update'),
                onPressed: _busy ? null : _updateZip,
                icon: const Icon(Icons.folder_zip_rounded),
                label: const Text('新しいZIPで更新'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('girls-group-admin-publish'),
                onPressed: _busy ? null : _publish,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('最新版を公開'),
              ),
              const SizedBox(height: 18),
              const Text(
                'グループでの表示',
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '現在の表示状態はgroup apps一覧APIには含まれないため、変更したい状態を明示して選びます。',
                style: TextStyle(fontSize: 12, color: _lavender),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('girls-group-admin-hide'),
                      onPressed: _busy ? null : () => _setHidden(true),
                      child: const Text('非表示にする'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('girls-group-admin-show'),
                      onPressed: _busy ? null : () => _setHidden(false),
                      child: const Text('再表示する'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('girls-group-admin-delete'),
                onPressed: _busy ? null : _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFA04455),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('グループから削除'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFC5CE)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFA04455),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
