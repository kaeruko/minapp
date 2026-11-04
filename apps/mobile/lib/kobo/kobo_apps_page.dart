import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../hosted_app_management_api.dart';
import '../hosted_authoring_contract_api.dart';
import '../hosted_authoring_editor_action.dart';
import '../hosted_builtin_install_api.dart';
import '../hosted_consumer_api.dart';
import '../hosted_consumer_errors.dart';
import '../hosted_my_apps_page.dart';
import '../hosted_source_archive.dart';
import '../hosted_upload_api.dart' hide maxHostedZipUploadBytes;
import 'kobo_components.dart';
import 'kobo_source_editor_page.dart';
import 'kobo_theme.dart';

const String _koboBlankAppHtml = '''<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>俺のアプリ</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      color: #1f1f23;
      background: #faf3e6;
      font-family: system-ui, "Yu Gothic", sans-serif;
    }
    main {
      width: min(100%, 520px);
      padding: 32px 24px;
      text-align: center;
      background: #f5e8d1;
      border: 1px solid #d8c8af;
      border-radius: 14px;
    }
    h1 { margin: 0 0 12px; color: #243a5a; }
    p { margin: 0; line-height: 1.7; }
  </style>
</head>
<body>
  <main>
    <h1>俺のアプリ</h1>
    <p>ここから自由に作り替えてみよう。</p>
  </main>
</body>
</html>
''';

class KoboAppsPage extends StatefulWidget {
  const KoboAppsPage({
    required this.api,
    required this.session,
    required this.onNavigationSelected,
    super.key,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession session;
  final ValueChanged<KoboNavigationItem> onNavigationSelected;

  @override
  State<KoboAppsPage> createState() => _KoboAppsPageState();
}

class _KoboAppsPageState extends State<KoboAppsPage> {
  late final HostedAppManagementApi _managementApi;
  late final HostedUploadApi _uploadApi;
  late final HostedBuiltinInstallApi _builtinInstallApi;
  late final HostedAuthoringContractApi _contractApi;
  List<HostedGroup>? _groups;
  List<ManagedHostedApp>? _apps;
  List<HostedAuthoringAppContract>? _makers;
  String? _groupId;
  bool _busy = false;
  bool _loadingMakers = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _managementApi = HostedAppManagementApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    _uploadApi = HostedUploadApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    _builtinInstallApi = HostedBuiltinInstallApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    _contractApi = HostedAuthoringContractApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    _load();
  }

  @override
  void dispose() {
    _managementApi.close();
    _uploadApi.close();
    _builtinInstallApi.close();
    _contractApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups =
          await widget.api.listGroups(widget.session.accessToken);
      final HostedGroup community =
          widget.api.edition.community.requireFrom(groups);
      final List<ManagedHostedApp> apps =
          await _managementApi.listApps(widget.session.accessToken);
      if (!mounted) return;
      final bool selectedStillExists =
          groups.any((HostedGroup group) => group.groupId == _groupId);
      setState(() {
        _groups = groups;
        _apps = apps;
        if (!selectedStillExists) {
          _groupId = community.groupId;
          _makers = null;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareMakers() async {
    final String? groupId = _groupId;
    if (groupId == null || _loadingMakers) return;
    setState(() {
      _loadingMakers = true;
      _error = null;
    });
    try {
      await _builtinInstallApi.ensureNovelEditor(
        accessToken: widget.session.accessToken,
        groupId: groupId,
        includeSample: false,
      );
      final List<HostedAuthoringAppContract> contracts =
          await _contractApi.listApps(
        accessToken: widget.session.accessToken,
        groupId: groupId,
      );
      final List<HostedAuthoringAppContract> makers = contracts
          .where(
            (HostedAuthoringAppContract contract) => contract.edits.isNotEmpty,
          )
          .toList(growable: false)
        ..sort(
          (HostedAuthoringAppContract a, HostedAuthoringAppContract b) =>
              a.title.compareTo(b.title),
        );
      if (mounted) setState(() => _makers = makers);
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _loadingMakers = false);
    }
  }

  Future<void> _openMaker(HostedAuthoringAppContract maker) async {
    final String? groupId = _groupId;
    if (groupId == null) return;
    await openHostedAuthoringProjects(
      context: context,
      baseUri: widget.api.baseUri,
      accessToken: widget.session.accessToken,
      groupId: groupId,
      editorAppId: maker.appId,
      runtimeTransport: widget.api.runtimeClient,
      editorFormats: maker.edits,
      errorMessage: hostedConsumerMessageFor,
      pageTitle: '${maker.title}でつくる',
      collectionTitle: 'つくった作品',
      emptyTitle: 'まだ作品がありません',
      emptyBody: '「新しくつくる」からはじめましょう。',
    );
  }

  List<ManagedHostedApp> _visibleApps() {
    final String? groupId = _groupId;
    if (groupId == null) return const <ManagedHostedApp>[];
    return (_apps ?? const <ManagedHostedApp>[])
        .where((ManagedHostedApp app) => app.app.groupId == groupId)
        .toList(growable: false);
  }

  Future<String?> _askTitle({required String initialValue}) {
    String title = initialValue;
    String? validationError;
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          void submit() {
            if (title.isEmpty || title != title.trim() || title.length > 80) {
              setDialogState(
                () => validationError = '前後に空白のない1〜80文字で入力してください。',
              );
              return;
            }
            Navigator.of(dialogContext).pop(title);
          }

          return AlertDialog(
            title: const Text('アプリ名を決める'),
            content: TextFormField(
              key: const Key('kobo-create-title'),
              initialValue: title,
              autofocus: true,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'アプリ名',
                hintText: '例：晩酌予算メモ',
                errorText: validationError,
              ),
              onChanged: (String value) => title = value,
              onFieldSubmitted: (_) => submit(),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('やめる'),
              ),
              FilledButton(
                key: const Key('kobo-create-confirm'),
                onPressed: submit,
                child: const Text('つくる'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createBlank() async {
    final String? groupId = _groupId;
    if (groupId == null || _busy) return;
    final String? title = await _askTitle(initialValue: '俺のアプリ');
    if (title == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedSourceArchive archive = HostedSourceArchive.fromEntries(
        <String, Uint8List>{
          'index.html': Uint8List.fromList(utf8.encode(_koboBlankAppHtml)),
        },
      );
      final HostedGroupApp app = await _uploadApi.createFromZip(
        accessToken: widget.session.accessToken,
        groupId: groupId,
        title: title,
        zipBytes: archive.encode(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _openEditor(app);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadZip() async {
    final String? groupId = _groupId;
    if (groupId == null || _busy) return;
    final PlatformFile? file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (file == null || !mounted) return;
    if (file.extension?.toLowerCase() != 'zip') {
      setState(() => _error = '拡張子 .zip のファイルを選んでください。');
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      if (mounted) setState(() => _error = 'ZIPを読み込めませんでした: $error');
      return;
    }
    if (bytes.isEmpty || bytes.length > maxHostedZipUploadBytes) {
      setState(() => _error = 'ZIPは1byte以上2MB以下にしてください。');
      return;
    }
    final String stem = file.name.toLowerCase().endsWith('.zip')
        ? file.name.substring(0, file.name.length - 4)
        : file.name;
    final String? title = await _askTitle(initialValue: stem);
    if (title == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroupApp app = await _uploadApi.createFromZip(
        accessToken: widget.session.accessToken,
        groupId: groupId,
        title: title,
        zipBytes: bytes,
      );
      final int? revision = app.sourceRevision;
      if (revision == null) {
        throw const FormatException('作成したアプリにsource revisionがありません。');
      }
      await _uploadApi.publish(
        accessToken: widget.session.accessToken,
        groupId: groupId,
        appId: app.appId,
        revision: revision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$title」を追加して公開しました')),
      );
      setState(() => _busy = false);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = hostedConsumerMessageFor(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor(HostedGroupApp app) async {
    final int? revision = app.sourceRevision;
    if (!app.editable || revision == null) {
      throw StateError('このアプリには編集可能なソースがありません。');
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => KoboSourceEditorPage(
          api: _managementApi,
          accessToken: widget.session.accessToken,
          groupId: app.groupId,
          appId: app.appId,
          title: app.title,
          expectedRevision: revision,
        ),
      ),
    );
  }

  Future<void> _openDetail(ManagedHostedApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedManagedAppDetailPage(
          baseUri: widget.api.baseUri,
          session: widget.session,
          appId: app.app.appId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedGroup>? groups = _groups;
    final List<ManagedHostedApp> apps = _visibleApps();
    return Scaffold(
      appBar: AppBar(
        title: const Text('つくる・俺のアプリ'),
        actions: <Widget>[
          IconButton(
            tooltip: '更新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(KoboSpacing.md),
          children: <Widget>[
            if (groups != null)
              DropdownButtonFormField<String>(
                key: const Key('kobo-app-group'),
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: '置き場所'),
                items: groups
                    .map(
                      (HostedGroup group) => DropdownMenuItem<String>(
                        value: group.groupId,
                        child: Text(group.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (String? value) => setState(() {
                          _groupId = value;
                          _makers = null;
                        }),
              ),
            const SizedBox(height: KoboSpacing.md),
            FilledButton.icon(
              key: const Key('kobo-create-blank-app'),
              onPressed: _busy || _groupId == null ? null : _createBlank,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('新しいアプリをつくる'),
            ),
            const SizedBox(height: KoboSpacing.xs),
            OutlinedButton.icon(
              key: const Key('kobo-upload-zip'),
              onPressed: _busy || _groupId == null ? null : _uploadZip,
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('ZIPから追加する'),
            ),
            const SizedBox(height: KoboSpacing.lg),
            const KoboSectionHeader(title: '作品メーカー'),
            const SizedBox(height: KoboSpacing.sm),
            if (_makers == null)
              OutlinedButton.icon(
                key: const Key('kobo-prepare-makers'),
                onPressed:
                    _loadingMakers || _groupId == null ? null : _prepareMakers,
                icon: _loadingMakers
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_stories_outlined),
                label: Text(
                  _loadingMakers ? '準備中…' : '作品メーカーを準備する',
                ),
              )
            else if (_makers!.isEmpty)
              const Text('この置き場所で使える作品メーカーはありません。')
            else
              for (final HostedAuthoringAppContract maker in _makers!)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.auto_stories_outlined,
                      color: KoboColors.navy,
                    ),
                    title: Text(maker.title),
                    subtitle: Text(maker.edits.join(' / ')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _loadingMakers ? null : () => _openMaker(maker),
                  ),
                ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: KoboSpacing.sm),
              Text(_error!, style: const TextStyle(color: KoboColors.error)),
            ],
            const SizedBox(height: KoboSpacing.lg),
            const KoboSectionHeader(title: '俺のアプリ'),
            const SizedBox(height: KoboSpacing.sm),
            if (_apps == null)
              const Center(child: CircularProgressIndicator())
            else if (apps.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(KoboSpacing.lg),
                  child: Text('この置き場所には、まだ自分のアプリがありません。'),
                ),
              )
            else
              for (final ManagedHostedApp app in apps) ...<Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(KoboSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(app.app.title, style: KoboTextStyles.cardTitle),
                        const SizedBox(height: KoboSpacing.xxs),
                        Text(
                          app.app.isPublished ? '公開中' : '下書き',
                          style: KoboTextStyles.secondary,
                        ),
                        const SizedBox(height: KoboSpacing.sm),
                        Wrap(
                          spacing: KoboSpacing.xs,
                          runSpacing: KoboSpacing.xs,
                          alignment: WrapAlignment.end,
                          children: <Widget>[
                            if (app.app.editable && app.sourceRevision != null)
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        await _openEditor(app.app);
                                        if (mounted) await _load();
                                      },
                                icon: const Icon(Icons.code_rounded),
                                label: const Text('コード編集'),
                              ),
                            FilledButton.tonalIcon(
                              onPressed: _busy ? null : () => _openDetail(app),
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('管理'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: KoboSpacing.sm),
              ],
          ],
        ),
      ),
      bottomNavigationBar: KoboBottomNavigation(
        selectedItem: KoboNavigationItem.create,
        onSelected: widget.onNavigationSelected,
      ),
    );
  }
}
