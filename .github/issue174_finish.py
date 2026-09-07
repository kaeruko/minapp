from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    if text.count(start) != 1:
        raise RuntimeError(f"{label}: start marker count is {text.count(start)}")
    left, tail = text.split(start, 1)
    if end not in tail:
        raise RuntimeError(f"{label}: end marker not found after start")
    _, right = tail.split(end, 1)
    return left + replacement + end + right


# Hosted group-app contract: ownership + editability/revision are explicit client data.
path = "apps/mobile/lib/hosted_api.dart"
text = read(path)
text = replace_once(
    text,
    "    this.builtinAssetPath,\n    required this.ownerUserId,\n  });",
    "    this.builtinAssetPath,\n    required this.ownerUserId,\n    required this.editable,\n    required this.sourceRevision,\n  });",
    "HostedGroupApp constructor fields",
)
text = replace_once(
    text,
    "  final String? builtinAssetPath;\n  final String ownerUserId;\n\n  bool get isPublished => publishedVersion != null;",
    "  final String? builtinAssetPath;\n  final String ownerUserId;\n  final bool editable;\n  final int? sourceRevision;\n\n  bool get isPublished => publishedVersion != null;",
    "HostedGroupApp model fields",
)
text = replace_once(
    text,
    "    final Object? publishedVersion = json['published_version'];\n    if (publishedVersion != null &&\n        (publishedVersion is! int || publishedVersion < 1)) {\n      throw const FormatException('Hosted group app has invalid published_version.');\n    }\n    return HostedGroupApp(",
    "    final Object? publishedVersion = json['published_version'];\n    if (publishedVersion != null &&\n        (publishedVersion is! int || publishedVersion < 1)) {\n      throw const FormatException('Hosted group app has invalid published_version.');\n    }\n    final Object? editable = json['editable'];\n    if (editable is! bool) {\n      throw const FormatException('Hosted group app has invalid editable.');\n    }\n    final Object? sourceRevision = json['source_revision'];\n    if (sourceRevision != null &&\n        (sourceRevision is! int || sourceRevision < 1)) {\n      throw const FormatException('Hosted group app has invalid source_revision.');\n    }\n    if (editable && sourceRevision == null) {\n      throw const FormatException('Editable hosted group app has no source_revision.');\n    }\n    return HostedGroupApp(",
    "HostedGroupApp strict editable/revision validation",
)
text = replace_once(
    text,
    "      builtinAssetPath: _optionalString(json, 'builtin_asset_path'),\n      ownerUserId: _requireHexId(json, 'owner_user_id'),\n    );",
    "      builtinAssetPath: _optionalString(json, 'builtin_asset_path'),\n      ownerUserId: _requireHexId(json, 'owner_user_id'),\n      editable: editable,\n      sourceRevision: sourceRevision as int?,\n    );",
    "HostedGroupApp parsed editability",
)
write(path, text)


# Shared management client: exact source download, group visibility, delete.
path = "apps/mobile/lib/hosted_app_management_api.dart"
text = read(path)
text = replace_once(
    text,
    "final RegExp _managedIdPattern = RegExp(r'^[0-9a-f]{32}$');\n\nclass HostedAppStats {",
    "final RegExp _managedIdPattern = RegExp(r'^[0-9a-f]{32}$');\nfinal RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');\n\nclass HostedSourceDownload {\n  const HostedSourceDownload({\n    required this.bytes,\n    required this.revision,\n    required this.sha256,\n  });\n\n  final Uint8List bytes;\n  final int revision;\n  final String sha256;\n}\n\nclass HostedAppStats {",
    "source download model",
)
source_methods = '''  Future<HostedSourceDownload> downloadSource({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    final http.Response response = await _client.get(
      _baseUri.resolve('/hosted/groups/$groupId/apps/$appId/source'),
      headers: <String, String>{
        'Accept': 'application/zip',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeJsonResponse(response);
      throw StateError('Unreachable source download error path.');
    }
    final String contentType =
        (response.headers['content-type'] ?? '').split(';', 1).first.trim().toLowerCase();
    if (contentType != 'application/zip') {
      throw FormatException(
        'Source download returned unexpected content type: $contentType.',
      );
    }
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > maxHostedZipUploadBytes) {
      throw const FormatException('Source download returned an invalid ZIP size.');
    }
    final int? revision = int.tryParse(
      response.headers['x-minapp-source-revision'] ?? '',
    );
    final String sha256 = response.headers['x-minapp-source-sha256'] ?? '';
    if (revision == null || revision < 1 || !_sha256Pattern.hasMatch(sha256)) {
      throw const FormatException('Source download metadata headers are invalid.');
    }
    return HostedSourceDownload(
      bytes: Uint8List.fromList(response.bodyBytes),
      revision: revision,
      sha256: sha256,
    );
  }

  Future<ManagedHostedApp> setGroupHidden({
    required String accessToken,
    required String groupId,
    required String appId,
    required bool hidden,
  }) async {
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    return ManagedHostedApp.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/groups/$groupId/apps/$appId/visibility',
        accessToken: accessToken,
        body: <String, Object?>{'hidden': hidden},
      ),
    );
  }

'''
text = replace_once(
    text,
    "  Future<int> updateSource({\n",
    source_methods + "  Future<int> updateSource({\n",
    "shared group management methods",
)
delete_method = '''  Future<void> deleteApp({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    final http.Response response = await _client.delete(
      _baseUri.resolve('/hosted/groups/$groupId/apps/$appId'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode == 204) {
      if (response.bodyBytes.isNotEmpty) {
        throw const FormatException('Delete response must have an empty body.');
      }
      return;
    }
    _decodeJsonResponse(response);
    throw StateError('Unreachable app deletion error path.');
  }

'''
text = replace_once(
    text,
    "  Future<Map<String, Object?>> _jsonRequest({\n",
    delete_method + "  Future<Map<String, Object?>> _jsonRequest({\n",
    "shared delete method",
)
write(path, text)


# Preview client: explicit author route and explicit group-management route share one strict parser.
path = "apps/mobile/lib/girls/girls_app_preview_api.dart"
text = read(path)
new_preview = '''  Future<GirlsAppTestSession> createDraftPreview({
    required String accessToken,
    required String groupId,
    required String appId,
  }) {
    return _createDraftPreview(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
      path: '/hosted/my/apps/$appId/preview-session',
    );
  }

  Future<GirlsAppTestSession> createGroupDraftPreview({
    required String accessToken,
    required String groupId,
    required String appId,
  }) {
    return _createDraftPreview(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
      path: '/hosted/groups/$groupId/apps/$appId/preview-session',
    );
  }

  Future<GirlsAppTestSession> _createDraftPreview({
    required String accessToken,
    required String groupId,
    required String appId,
    required String path,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');

    final Map<String, Object?> content = await _postEmpty(
      path: path,
      accessToken: accessToken,
    );
    _requireExactFields(
      content,
      const <String>{
        'app_id',
        'group_id',
        'source_revision',
        'content_path',
        'expires_in',
        'runtime_token',
        'runtime_expires_in',
      },
      'Draft preview session response',
    );
    if (_requiredString(content, 'app_id') != appId ||
        _requiredString(content, 'group_id') != groupId) {
      throw const FormatException(
        'Draft preview session returned a different app or group.',
      );
    }
    final int sourceRevision = _requiredPositiveInt(
      content,
      'source_revision',
    );
    final String contentPath = _requiredString(content, 'content_path');
    if (!_previewContentPathPattern.hasMatch(contentPath)) {
      throw const FormatException(
        'Draft preview session returned an invalid content path.',
      );
    }
    final int contentExpiresIn = _requiredPositiveInt(content, 'expires_in');
    final String runtimeToken = _requiredString(content, 'runtime_token');
    if (!_runtimeTokenPattern.hasMatch(runtimeToken)) {
      throw const FormatException(
        'Draft preview session returned an invalid Runtime token.',
      );
    }
    final int runtimeExpiresIn = _requiredPositiveInt(
      content,
      'runtime_expires_in',
    );

    return GirlsAppTestSession(
      contentUri: _baseUri.resolve(contentPath),
      contentExpiresIn: contentExpiresIn,
      runtimeToken: runtimeToken,
      runtimeExpiresIn: runtimeExpiresIn,
      sourceRevision: sourceRevision,
      publishedVersion: null,
    );
  }

'''
text = replace_between(
    text,
    "  Future<GirlsAppTestSession> createDraftPreview({\n",
    "  Future<_RuntimeSession> _createRuntimeSession({\n",
    new_preview,
    "draft preview methods",
)
write(path, text)


# Girls group page: owner/admin management is a separate route from My Apps.
path = "apps/mobile/lib/girls/girls_app_core.dart"
text = read(path)
text = replace_once(
    text,
    "import 'hosted_app_webview.dart';\nimport 'hosted_girls_api.dart';",
    "import 'hosted_app_webview.dart';\nimport 'girls_group_app_management_page.dart';\nimport 'hosted_girls_api.dart';",
    "Girls group management import",
)
open_manage = '''  Future<void> _openManagedApp(HostedGroupApp app) async {
    if (!widget.group.isOwner || !app.editable) {
      throw StateError('Group app management requires owner role and editable app.');
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

'''
text = replace_once(
    text,
    "  Future<void> _issueGroupId() async {\n",
    open_manage + "  Future<void> _issueGroupId() async {\n",
    "Girls group admin navigation",
)
text = replace_once(
    text,
    "                                  loading: _launchingAppId == app.appId,\n                                  onTap: () => _launchHostedApp(app),\n",
    "                                  loading: _launchingAppId == app.appId,\n                                  onTap: () => _launchHostedApp(app),\n                                  onManage: widget.group.isOwner && app.editable\n                                      ? () => _openManagedApp(app)\n                                      : null,\n",
    "Girls group app management button wiring",
)
text = replace_once(
    text,
    "  const _HostedAppTile({\n    required this.app,\n    required this.loading,\n    required this.onTap,\n  });\n\n  final HostedGroupApp app;\n  final bool loading;\n  final VoidCallback onTap;",
    "  const _HostedAppTile({\n    required this.app,\n    required this.loading,\n    required this.onTap,\n    required this.onManage,\n  });\n\n  final HostedGroupApp app;\n  final bool loading;\n  final VoidCallback onTap;\n  final VoidCallback? onManage;",
    "Hosted app tile management callback",
)
text = replace_once(
    text,
    "              if (loading)\n                const SizedBox.square(\n                  dimension: 20,\n                  child: CircularProgressIndicator(strokeWidth: 2),\n                )\n              else\n                const Icon(Icons.chevron_right_rounded, color: _lavender),",
    "              if (onManage != null)\n                IconButton(\n                  key: ValueKey<String>('girls-group-manage-${app.appId}'),\n                  tooltip: 'グループ管理',\n                  onPressed: loading ? null : onManage,\n                  icon: const Icon(Icons.settings_rounded, color: _lavenderDark),\n                ),\n              if (loading)\n                const SizedBox.square(\n                  dimension: 20,\n                  child: CircularProgressIndicator(strokeWidth: 2),\n                )\n              else\n                const Icon(Icons.chevron_right_rounded, color: _lavender),",
    "Hosted app tile management icon",
)
write(path, text)


# Author My Apps: expose exact source download and deletion in the author route.
path = "apps/mobile/lib/girls/girls_apps_page.dart"
text = read(path)
download_author = '''  Future<void> _downloadZip() async {
    final ManagedGirlsAppDetail? detail = _detail;
    final int? revision = detail?.summary.sourceRevision;
    if (detail == null || revision == null) {
      setState(() => _error = '保存するrevisionを確認できません。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedSourceDownload download = await _managementApi.downloadSource(
        accessToken: widget.session.accessToken,
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
      );
      if (download.revision != revision) {
        throw StateError(
          'Downloaded source revision ${download.revision} does not match $revision.',
        );
      }
      final String? savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'ZIPを保存',
        fileName: 'minapp-${detail.summary.app.appId}.zip',
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

'''
text = replace_once(
    text,
    "  Future<void> _updateZip() async {\n",
    download_author + "  Future<void> _updateZip() async {\n",
    "author source download method",
)
delete_author = '''  Future<void> _delete() async {
    final ManagedGirlsAppDetail? detail = _detail;
    if (detail == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('このアプリを削除する？'),
        content: Text('「${detail.summary.app.title}」を削除します。この操作は取り消せません。'),
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
        groupId: detail.summary.app.groupId,
        appId: detail.summary.app.appId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

'''
text = replace_once(
    text,
    "  @override\n  Widget build(BuildContext context) {\n    final ManagedGirlsAppDetail? detail = _detail;",
    delete_author + "  @override\n  Widget build(BuildContext context) {\n    final ManagedGirlsAppDetail? detail = _detail;",
    "author delete method",
)
text = replace_once(
    text,
    "              const SizedBox(height: 14),\n              Row(\n                children: <Widget>[\n                  Expanded(\n                    child: OutlinedButton.icon(\n                      onPressed: _busy ? null : _updateZip,\n                      icon: const Icon(Icons.folder_zip_rounded),\n                      label: const Text('新しいZIPで更新'),\n                    ),\n                  ),\n                ],\n              ),",
    "              const SizedBox(height: 14),\n              OutlinedButton.icon(\n                key: const Key('girls-app-download-source'),\n                onPressed: _busy ? null : _downloadZip,\n                icon: const Icon(Icons.download_rounded),\n                label: const Text('現在のZIPを保存'),\n              ),\n              const SizedBox(height: 8),\n              Row(\n                children: <Widget>[\n                  Expanded(\n                    child: OutlinedButton.icon(\n                      onPressed: _busy ? null : _updateZip,\n                      icon: const Icon(Icons.folder_zip_rounded),\n                      label: const Text('新しいZIPで更新'),\n                    ),\n                  ),\n                ],\n              ),",
    "author source download button",
)
text = replace_once(
    text,
    "              OutlinedButton.icon(\n                onPressed: _busy ? null : _toggleHidden,\n                icon: Icon(\n                  detail.summary.isHidden\n                      ? Icons.visibility_rounded\n                      : Icons.visibility_off_rounded,\n                ),\n                label: Text(detail.summary.isHidden ? '再公開する' : '非表示にする'),\n              ),\n              const SizedBox(height: 24),",
    "              OutlinedButton.icon(\n                onPressed: _busy ? null : _toggleHidden,\n                icon: Icon(\n                  detail.summary.isHidden\n                      ? Icons.visibility_rounded\n                      : Icons.visibility_off_rounded,\n                ),\n                label: Text(detail.summary.isHidden ? '再公開する' : '非表示にする'),\n              ),\n              const SizedBox(height: 8),\n              OutlinedButton.icon(\n                key: const Key('girls-app-delete'),\n                onPressed: _busy ? null : _delete,\n                style: OutlinedButton.styleFrom(\n                  foregroundColor: const Color(0xFFA04455),\n                ),\n                icon: const Icon(Icons.delete_outline_rounded),\n                label: const Text('アプリを削除'),\n              ),\n              const SizedBox(height: 24),",
    "author delete button",
)
write(path, text)
