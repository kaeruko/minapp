import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../hosted_app_webview.dart';
import '../hosted_authoring_contract_api.dart';
import '../hosted_authoring_editor_action.dart';
import '../hosted_authoring_projects_api.dart';
import 'api.dart';
import 'girls_errors.dart';
import 'girls_app_management_api.dart';
import 'girls_app_source_editor_page.dart';
import 'girls_apps_cache.dart';
import 'girls_apps_page.dart' as legacy;
import 'girls_builtin_install_api.dart';
import 'girls_footer_nav.dart';
import 'girls_scaffold.dart';
import 'girls_source_zip.dart';
import 'girls_zip_upload_page.dart';
import 'hosted_girls_api.dart';
import 'hosted_girls_upload_api.dart';

const Color _ink = Color(0xFF604943);
const Color _lavender = Color(0xFF745B9E);
const Color _pink = Color(0xFFF9DDE8);
const String _novelContentFormat = 'minapp/novel@1';
const String _blankAppStarterHtml = '''<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>わたしのアプリ</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Yu Gothic", sans-serif;
      color: #604943;
      background: linear-gradient(160deg, #fff7fb, #fff4df);
    }
    main {
      width: min(100%, 520px);
      padding: 32px 24px;
      text-align: center;
      background: rgba(255, 255, 255, .9);
      border: 2px solid #f0dfe8;
      border-radius: 28px;
      box-shadow: 0 12px 32px rgba(139, 107, 178, .12);
    }
    h1 { margin: 0 0 12px; }
    p { margin: 0; line-height: 1.7; }
  </style>
</head>
<body>
  <main>
    <h1>わたしのアプリ</h1>
    <p>ここから自由にアレンジしてみよう ✨</p>
  </main>
</body>
</html>
''';

String _novelProjectTitle(HostedAuthoringProject project) {
  if (project.summary.contentFormat != _novelContentFormat) {
    throw const FormatException(
        'Novel project has an unexpected content format.');
  }
  if (project.document.isEmpty) return '新しいノベル';
  final Object? rawTitle = project.document['title'];
  if (rawTitle is! String ||
      rawTitle.isEmpty ||
      rawTitle != rawTitle.trim() ||
      rawTitle.length > 80) {
    throw const FormatException('Novel project document has an invalid title.');
  }
  return rawTitle;
}

/// Girls app hub with a format-neutral maker section.
///
/// Editor/Player registration remains a developer concern. The app only shows
/// published Editors that the current group can actually use, while ordinary
/// ZIP apps stay in the separate app-management list.
class GirlsAppsPage extends StatefulWidget {
  const GirlsAppsPage({
    required this.api,
    required this.session,
    this.onHome,
    this.onGroups,
    this.currentGroup,
    this.onCurrentGroupChanged,
    this.onFooterVisibilityChanged,
    this.cache,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final VoidCallback? onHome;
  final VoidCallback? onGroups;
  final HostedGroup? currentGroup;
  final ValueChanged<HostedGroup?>? onCurrentGroupChanged;
  final ValueChanged<bool>? onFooterVisibilityChanged;
  final GirlsAppsCache? cache;

  @override
  State<GirlsAppsPage> createState() => _GirlsAppsPageState();
}

class _GirlsAppsPageState extends State<GirlsAppsPage> {
  late final GirlsAppManagementApi _managementApi;
  late final GirlsBuiltinInstallApi _builtinInstallApi;
  late final HostedAuthoringContractApi _contractApi;

  List<ManagedGirlsApp>? _apps;
  List<HostedAuthoringAppContract>? _makers;
  List<HostedGroup>? _activeGroups;
  HostedGroup? _currentGroup;
  String? _novelEditorAppId;
  bool _busy = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.currentGroup;
    _managementApi = GirlsAppManagementApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _builtinInstallApi = GirlsBuiltinInstallApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _contractApi = HostedAuthoringContractApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    final GirlsAppsSnapshot? cached =
        widget.cache?.read(widget.session.accessToken, _currentGroup?.groupId);
    if (cached != null) {
      _activeGroups = cached.groups;
      _makers = cached.makers;
      _apps = cached.apps;
      _novelEditorAppId = cached.novelEditorAppId;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant GirlsAppsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentGroup?.groupId != oldWidget.currentGroup?.groupId ||
        widget.session.accessToken != oldWidget.session.accessToken) {
      _currentGroup = widget.currentGroup;
      _makers = null;
      _apps = null;
      _activeGroups = null;
      _novelEditorAppId = null;
      _load();
    }
  }

  @override
  void dispose() {
    _managementApi.close();
    _builtinInstallApi.close();
    _contractApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final int generation = ++_loadGeneration;
    final Stopwatch loadTime = Stopwatch()..start();
    final bool hadSnapshot = _makers != null && _apps != null;
    final String accessToken = widget.session.accessToken;
    final String? previousId = _currentGroup?.groupId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedGroup> groups = await widget.api.listGroups(
        accessToken,
      );
      if (!mounted || generation != _loadGeneration) return;
      HostedGroup? currentGroup;
      if (previousId != null) {
        for (final HostedGroup group in groups) {
          if (group.groupId == previousId) {
            currentGroup = group;
            break;
          }
        }
      }
      currentGroup ??= groups.length == 1 ? groups.single : null;

      if (currentGroup == null) {
        if (!mounted) return;
        setState(() {
          _activeGroups = groups;
          _currentGroup = null;
          _makers = const <HostedAuthoringAppContract>[];
          _apps = const <ManagedGirlsApp>[];
          _novelEditorAppId = null;
        });
        widget.cache?.clear();
        if (previousId != null) widget.onCurrentGroupChanged?.call(null);
        return;
      }

      // Discover makers and managed apps concurrently. Sample artwork belongs
      // to opening the Novel maker, not to displaying the app list.
      final results = await (
        _loadMakers(accessToken, currentGroup.groupId),
        _managementApi.listApps(accessToken),
      ).wait;
      final HostedGroupApp novelEditor = results.$1.$1;
      final List<HostedAuthoringAppContract> contracts = results.$1.$2;
      final List<ManagedGirlsApp> managed = results.$2;

      final Set<String> authoringAppIds = contracts
          .map((HostedAuthoringAppContract contract) => contract.appId)
          .toSet();
      final List<HostedAuthoringAppContract> makers = contracts
          .where((HostedAuthoringAppContract contract) =>
              contract.edits.isNotEmpty)
          .toList(growable: false)
        ..sort((a, b) {
          if (a.appId == novelEditor.appId) return -1;
          if (b.appId == novelEditor.appId) return 1;
          final int byTitle = a.title.compareTo(b.title);
          return byTitle != 0 ? byTitle : a.appId.compareTo(b.appId);
        });
      final List<ManagedGirlsApp> apps = managed
          .where(
            (ManagedGirlsApp app) =>
                app.app.groupId == currentGroup!.groupId &&
                !authoringAppIds.contains(app.app.appId),
          )
          .toList(growable: false);

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _activeGroups = groups;
        _currentGroup = currentGroup;
        _makers = makers;
        _apps = apps;
        _novelEditorAppId = novelEditor.appId;
      });
      widget.cache?.write(
          accessToken,
          GirlsAppsSnapshot(
            group: currentGroup,
            novelEditorAppId: novelEditor.appId,
            groups: groups,
            makers: makers,
            apps: apps,
          ));
      assert(() {
        debugPrint('Girls apps loaded in ${loadTime.elapsedMilliseconds} ms '
            '(previous list visible: $hadSnapshot)');
        return true;
      }());
      if (previousId != currentGroup.groupId) {
        widget.onCurrentGroupChanged?.call(currentGroup);
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        widget.cache?.clear();
        setState(() {
          _error = girlsMessageFor(_loadError(error));
          _makers = const [];
          _apps = const [];
          _activeGroups = null;
          _novelEditorAppId = null;
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<(HostedGroupApp, List<HostedAuthoringAppContract>)> _loadMakers(
    String accessToken,
    String groupId,
  ) async {
    final editor = await _builtinInstallApi.ensureNovelEditor(
        accessToken: accessToken, groupId: groupId, includeSample: false);
    final contracts =
        await _contractApi.listApps(accessToken: accessToken, groupId: groupId);
    return (editor, contracts);
  }

  Object _loadError(Object error) {
    if (error is ParallelWaitError<Object?, (AsyncError?, AsyncError?)>) {
      final errors = error.errors;
      return errors.$1?.error ?? errors.$2!.error;
    }
    return error;
  }

  Future<String?> _askBlankAppTitle() async {
    String title = 'わたしのアプリ';
    String? validationError;
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (
          BuildContext context,
          void Function(void Function()) setDialogState,
        ) {
          void submit() {
            final String raw = title;
            if (raw.isEmpty) {
              setDialogState(() => validationError = 'アプリ名を入力してね。');
              return;
            }
            if (raw != raw.trim()) {
              setDialogState(() => validationError = '前後の空白を消してね。');
              return;
            }
            if (raw.length > 80) {
              setDialogState(
                () => validationError = 'アプリ名は80文字までだよ。',
              );
              return;
            }
            Navigator.of(dialogContext).pop(raw);
          }

          return AlertDialog(
            key: const Key('girls-create-blank-app-dialog'),
            title: const Text('新しいアプリをつくる'),
            content: TextFormField(
              key: const Key('girls-create-blank-app-title'),
              initialValue: title,
              autofocus: true,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              onChanged: (String value) => title = value,
              onFieldSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: 'アプリ名',
                hintText: '例：推し活タイマー',
                errorText: validationError,
              ),
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('girls-create-blank-app-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('やめる'),
              ),
              FilledButton.icon(
                key: const Key('girls-create-blank-app-confirm'),
                onPressed: submit,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('つくる'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createBlankApp() async {
    final HostedGroup? group = _currentGroup;
    if (group == null) {
      setState(() => _error = '先に「グループ」から、いま使うグループを選んでね。');
      return;
    }
    final String? title = await _askBlankAppTitle();
    if (title == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final HostedGirlsUploadApi uploadApi = HostedGirlsUploadApi(
      baseUri: widget.api.baseUri,
      client: widget.api.httpClient,
    );
    try {
      final GirlsSourceArchive archive = GirlsSourceArchive.fromEntries(
        <String, Uint8List>{
          'index.html': Uint8List.fromList(utf8.encode(_blankAppStarterHtml)),
        },
      );
      final HostedGroupApp created = await uploadApi.createFromZip(
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
        title: title,
        zipBytes: archive.encode(),
      );
      if (created.groupId != group.groupId ||
          !created.editable ||
          created.sourceRevision != 1 ||
          created.sourceKind != 'zip') {
        throw const FormatException(
          'New app response changed the requested app scope.',
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (BuildContext context) => GirlsAppSourceEditorPage(
            api: _managementApi,
            accessToken: widget.session.accessToken,
            groupId: group.groupId,
            appId: created.appId,
            title: created.title,
            expectedRevision: created.sourceRevision!,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      uploadApi.close();
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _openZipUpload() async {
    final HostedGroup? group = _currentGroup;
    final List<HostedGroup>? groups = _activeGroups;
    if (groups == null) return;
    if (groups.isEmpty) {
      setState(() => _error = 'アプリを追加するには、参加中のグループが必要です。');
      return;
    }
    if (group == null) {
      setState(() => _error = '先に「グループ」から、いま使うグループを選んでね。');
      return;
    }

    final List<HostedGroup> orderedGroups = <HostedGroup>[
      group,
      ...groups.where((HostedGroup candidate) => candidate.groupId != group.groupId),
    ];
    setState(() => _error = null);
    final bool? uploaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => GirlsZipUploadPage(
          api: widget.api,
          session: widget.session,
          activeGroups: orderedGroups,
        ),
      ),
    );
    if (uploaded == true && mounted) await _load();
  }

  Future<void> _openMaker(HostedAuthoringAppContract maker) async {
    final HostedGroup? group = _currentGroup;
    if (group == null) {
      setState(() => _error = '先に「グループ」から、いま使うグループを選んでね。');
      return;
    }

    final bool isNovel = maker.appId == _novelEditorAppId &&
        maker.edits.length == 1 &&
        maker.edits.single == _novelContentFormat;
    if (isNovel) widget.onFooterVisibilityChanged?.call(true);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (isNovel) {
        await _builtinInstallApi.ensureNovelSampleProject(
            accessToken: widget.session.accessToken, groupId: group.groupId);
        if (!mounted) return;
      }
      await openHostedAuthoringProjects(
        context: context,
        baseUri: widget.api.baseUri,
        accessToken: widget.session.accessToken,
        groupId: group.groupId,
        editorAppId: maker.appId,
        runtimeTransport: widget.api.runtimeClient,
        editorFormats: maker.edits,
        errorMessage: girlsMessageFor,
        pageTitle: isNovel ? 'ノベルエディタ' : '${maker.title}でつくる',
        collectionTitle: isNovel ? 'あなたのノベル作品' : 'あなたの作品',
        emptyTitle: isNovel ? 'まだノベル作品がありません' : 'まだ作品がありません',
        emptyBody: isNovel ? '「新しくつくる」から物語を作ってみよう。' : '「新しくつくる」からはじめよう。',
        projectTitle: isNovel ? _novelProjectTitle : null,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
      if (isNovel) widget.onFooterVisibilityChanged?.call(false);
    }
  }

  Future<void> _openDetail(ManagedGirlsApp app) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => legacy.GirlsAppDetailPage(
          api: widget.api,
          session: widget.session,
          appId: app.app.appId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _launchPublishedApp(ManagedGirlsApp app) async {
    if (!app.app.isPublished || app.isHidden) {
      throw StateError(
        'Published app launch requires a visible published app.',
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final launch = await widget.api.createLaunch(
        accessToken: widget.session.accessToken,
        groupId: app.app.groupId,
        appId: app.app.appId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage(
            title: app.app.title,
            launch: launch,
            runtimeTransport: widget.api.runtimeClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedAuthoringAppContract>? makers = _makers;
    final List<ManagedGirlsApp>? apps = _apps;
    return GirlsScaffold(
      title: 'アプリ',
      actions: <Widget>[
        IconButton(
          tooltip: '更新',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: <Widget>[
            _CurrentGroupCard(group: _currentGroup, onChange: widget.onGroups),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('girls-create-blank-app'),
              onPressed: _busy ? null : _createBlankApp,
              style: FilledButton.styleFrom(
                backgroundColor: _lavender,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text(
                '新しいアプリをつくる',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              key: const Key('girls-my-apps-upload'),
              onPressed: _busy ? null : _openZipUpload,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.folder_zip_rounded),
              label: const Text('ZIPからアプリを追加'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
              TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('もう一度読み込む')),
            ],
            if (_busy && makers != null) const LinearProgressIndicator(),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: '作品をつくる',
              subtitle: '使えるメーカーから作品をつくれるよ',
            ),
            const SizedBox(height: 10),
            if (makers == null)
              const _LoadingCard()
            else if (_currentGroup == null)
              _SelectGroupCard(onSelect: widget.onGroups)
            else if (_error != null && makers.isEmpty)
              const SizedBox.shrink()
            else if (makers.isEmpty)
              const _EmptyMakerCard()
            else
              ...makers.map(
                (HostedAuthoringAppContract maker) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MakerCard(
                    maker: maker,
                    isDefault: maker.appId == _novelEditorAppId,
                    onTap: _busy ? null : () => _openMaker(maker),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const _SectionHeader(title: 'あなたのアプリ'),
            const SizedBox(height: 10),
            if (apps == null)
              const _LoadingCard()
            else if (_currentGroup == null)
              _SelectGroupCard(onSelect: widget.onGroups)
            else if (_error != null && apps.isEmpty)
              const SizedBox.shrink()
            else if (apps.isEmpty)
              const _EmptyAppsCard()
            else
              ...apps.map(
                (ManagedGirlsApp app) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AppCard(
                    app: app,
                    onTap: _busy ? null : () => _openDetail(app),
                    onPlayPublished:
                        _busy || !app.app.isPublished || app.isHidden
                            ? null
                            : () => _launchPublishedApp(app),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: GirlsFooterNav(
        selectedTab: GirlsFooterTab.apps,
        enabledTabs: <GirlsFooterTab>{
          if (widget.onHome != null) GirlsFooterTab.home,
          if (widget.onGroups != null) GirlsFooterTab.groups,
          GirlsFooterTab.apps,
          GirlsFooterTab.more,
        },
        onSelected: (GirlsFooterTab tab) {
          if (tab == GirlsFooterTab.home) widget.onHome?.call();
          if (tab == GirlsFooterTab.groups) widget.onGroups?.call();
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
              color: _ink, fontSize: 19, fontWeight: FontWeight.w900),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(subtitle!, style: const TextStyle(color: Color(0xFF8C7893))),
        ],
      ],
    );
  }
}

class _CurrentGroupCard extends StatelessWidget {
  const _CurrentGroupCard({required this.group, required this.onChange});

  final HostedGroup? group;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEADDEB)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.group_rounded, color: _lavender),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group == null ? 'グループを選んでね' : group!.name,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
            ),
          ),
          if (onChange != null)
            TextButton(onPressed: onChange, child: const Text('変更')),
        ],
      ),
    );
  }
}

class _MakerCard extends StatelessWidget {
  const _MakerCard({
    required this.maker,
    required this.isDefault,
    required this.onTap,
  });

  final HostedAuthoringAppContract maker;
  final bool isDefault;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('girls-maker-${maker.appId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: _pink, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.edit_note_rounded, color: _lavender),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      maker.title,
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isDefault
                          ? '物語や選択肢をつくれるよ'
                          : maker.edits.length == 1
                              ? 'このメーカーで作品をつくる'
                              : '${maker.edits.length}種類の作品をつくれる',
                      style: const TextStyle(color: Color(0xFF8C7893)),
                    ),
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

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.onTap,
    required this.onPlayPublished,
  });

  final ManagedGirlsApp app;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPublished;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(17),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        leading: const Icon(Icons.apps_rounded, color: _lavender),
        title: Text(app.app.title,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        subtitle: Text(app.isHidden ? '非公開' : '公開中'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (onPlayPublished != null)
              IconButton(
                key: ValueKey<String>(
                  'girls-app-play-published-${app.app.appId}',
                ),
                tooltip: '公開版で遊ぶ',
                onPressed: onPlayPublished,
                icon: const Text('▶️', style: TextStyle(fontSize: 21)),
              ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _SelectGroupCard extends StatelessWidget {
  const _SelectGroupCard({required this.onSelect});
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onSelect,
        icon: const Icon(Icons.group_rounded),
        label: const Text('使うグループを選ぶ'),
      );
}

class _EmptyMakerCard extends StatelessWidget {
  const _EmptyMakerCard();

  @override
  Widget build(BuildContext context) => const Text(
        '使えるメーカーがまだありません。',
        style: TextStyle(color: Color(0xFF8C7893)),
      );
}

class _EmptyAppsCard extends StatelessWidget {
  const _EmptyAppsCard();

  @override
  Widget build(BuildContext context) => const Text(
        '追加したアプリはまだありません。',
        style: TextStyle(color: Color(0xFF8C7893)),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
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
            color: Color(0xFFA04455), fontWeight: FontWeight.w700),
      ),
    );
  }
}
