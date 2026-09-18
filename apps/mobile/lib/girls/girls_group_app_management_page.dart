import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../hosted_app_webview.dart';
import 'api.dart';
import 'girls_errors.dart';
import 'girls_app_management_api.dart';
import 'girls_app_preview_api.dart';
import 'girls_app_source_editor_page.dart';
import 'girls_shop_api.dart';
import 'hosted_girls_api.dart';
import 'hosted_girls_upload_api.dart';

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
  late final GirlsShopApi _shopApi;
  HostedGroupApp? _app;
  String? _authorLabel;
  bool? _shopListed;
  bool _busy = false;
  bool _shopBusy = false;
  String? _error;
  String? _shopError;

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
    _shopApi = GirlsShopApi(baseUri: widget.api.baseUri);
    _load();
  }

  @override
  void dispose() {
    _managementApi.close();
    _previewApi.close();
    _shopApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _shopError = null;
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

      bool? shopListed;
      String? shopError;
      try {
        final List<GirlsShopApp> shopApps =
            await _shopApi.listApps(widget.session.accessToken);
        final int matchesInShop =
            shopApps.where((GirlsShopApp item) => item.appId == app.appId).length;
        if (matchesInShop > 1) {
          throw StateError('Girls shop returned duplicate app_id entries.');
        }
        shopListed = matchesInShop == 1;
      } catch (error) {
        shopError = girlsMessageFor(error);
      }

      if (!mounted) return;
      setState(() {
        _app = app;
        _authorLabel = authorLabel;
        _shopListed = shopListed;
        _shopError = shopError;
      });
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
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

  Future<void> _setShopListed(bool listed) async {
    final HostedGroupApp app = _requireEditableApp();
    if (!app.isPublished) {
      throw StateError('Unpublished app cannot be listed in the Girls shop.');
    }
    if (_shopBusy) return;
    setState(() {
      _shopBusy = true;
      _shopError = null;
    });
    try {
      await _shopApi.setVisibility(
        accessToken: widget.session.accessToken,
        appId: app.appId,
        listed: listed,
      );
      if (!mounted) return;
      setState(() => _shopListed = listed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            listed ? 'Girlsショップに公開しました。' : 'Girlsショップから取り下げました。',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _shopError = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
  }

  Future<void> _downloadZip() async {
    final HostedGroupApp app = _requireEditableApp();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GirlsSourceDownload download = await _managementApi.downloadSource(
        accessToken: widget.session.accessToken,
        groupId: widget.group.groupId,
        appId: app.appId,
      );
      if (download.revision != app.sourceRevision) {
        throw StateError(
          'Downloaded source revision ${download.revision} does not match the loaded revision ${app.sourceRevision}.',
        );
      }
      final Uri? savedPath = await FilePicker.saveFile(
        dialogTitle: 'ZIPを保存',
        fileName: 'minapp-${app.appId}.zip',
        bytes: download.bytes,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ZIPを保存しました。')));
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSource() async {
    final HostedGroupApp app = _requireEditableApp();
    final int? revision = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (BuildContext context) => GirlsAppSourceEditorPage(
          api: _managementApi,
          accessToken: widget.session.accessToken,
          groupId: widget.group.groupId,
          appId: app.appId,
          title: app.title,
          expectedRevision: app.sourceRevision!,
        ),
      ),
    );
    if (revision == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('コードを保存しました。編集版を更新しました。')),
    );
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
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
      final GirlsAppTestSession launch = await _previewApi
          .createGroupDraftPreview(
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
            title: '${app.title}（下書きを開く）',
            contentUri: launch.contentUri,
            runtimeToken: launch.runtimeToken,
            runtimeTransport: GirlsPreviewRuntimeTransport(
              delegate: widget.api.runtimeClient,
              previewApi: _previewApi,
              accessToken: widget.session.accessToken,
              groupId: app.groupId,
              appId: app.appId,
              runtimeToken: launch.runtimeToken,
              groupScope: true,
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
        SnackBar(content: Text(hidden ? 'アプリを非表示にしました。' : 'アプリを再表示しました。')),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
      if (mounted) setState(() => _error = girlsMessageFor(error));
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
                    Text('編集版: ${app.sourceRevision == null ? 'なし' : '保存済み'}'),
                    Text('公開版: ${app.publishedVersion == null ? 'なし' : 'あり'}'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'この作品は、みんアプ内で動くミニアプリとして開きます。',
                style: TextStyle(fontSize: 12, color: _lavender),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                key: const Key('girls-group-admin-preview'),
                onPressed: _busy ? null : _previewDraft,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('下書きを開く'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('girls-group-admin-edit-code'),
                onPressed: _busy ? null : _editSource,
                icon: const Icon(Icons.code_rounded),
                label: const Text('コードを編集'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('girls-group-admin-download'),
                onPressed: _busy ? null : _downloadZip,
                icon: const Icon(Icons.download_rounded),
                label: const Text('編集のZIPを保存'),
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
                label: const Text('編集版を公開'),
              ),
              const SizedBox(height: 22),
              const Text(
                'みんアプGirls ショップ',
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              if (!app.isPublished)
                const Text(
                  '編集版を公開すると、ほかのグループのみんなが見られるショップへ出せるようになります。',
                  style: TextStyle(fontSize: 12, color: _lavender),
                )
              else ...<Widget>[
                const Text(
                  'ONにすると、このグループの外からも作品を見つけて遊んだりZIPを受け取ったりできます。',
                  style: TextStyle(fontSize: 12, color: _lavender),
                ),
                if (_shopError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  _AdminError(message: 'ショップ状態を確認できませんでした。$_shopError'),
                ],
                const SizedBox(height: 4),
                if (_shopListed == null && _shopError == null)
                  const LinearProgressIndicator()
                else if (_shopListed != null)
                  SwitchListTile(
                    key: const Key('girls-group-admin-shop-listing'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Girlsショップに公開'),
                    subtitle: Text(
                      _shopListed! ? 'ショップ掲載中' : 'このグループだけで公開中',
                    ),
                    value: _shopListed!,
                    onChanged: _busy || _shopBusy ? null : _setShopListed,
                  ),
              ],
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
                '編集の表示状態はgroup apps一覧APIには含まれないため、変更したい状態を明示して選びます。',
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
