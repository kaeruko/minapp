import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../hosted_app_webview.dart';
import '../hosted_authoring_bridge.dart';
import '../hosted_authoring_launch_client.dart';
import '../hosted_authoring_preview_client.dart';
import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_builtin_install_api.dart';
import 'girls_novel_authoring_api.dart';
import 'hosted_girls_api.dart';

const Color _novelLavender = Color(0xFF745B9E);
const Color _novelInk = Color(0xFF604943);
const Color _novelSurface = Color(0xFFFFFBFD);

class GirlsNovelProjectsPage extends StatefulWidget {
  const GirlsNovelProjectsPage({
    required this.api,
    required this.session,
    required this.editorApp,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final HostedGroupApp editorApp;

  @override
  State<GirlsNovelProjectsPage> createState() => _GirlsNovelProjectsPageState();
}

class _GirlsNovelProjectsPageState extends State<GirlsNovelProjectsPage> {
  late final http.Client _client;
  late final GirlsNovelAuthoringApi _projectsApi;
  late final GirlsBuiltinInstallApi _builtinInstallApi;
  late final HostedAuthoringLaunchApiClient _launchApi;
  late final HostedAuthoringPreviewApiClient _previewApi;
  late final HostedAuthoringApiClient _authoringTransport;

  List<GirlsNovelProject>? _projects;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _validateEditorApp();
    _client = http.Client();
    _projectsApi = GirlsNovelAuthoringApi(
      baseUri: widget.api.baseUri,
      client: _client,
    );
    _builtinInstallApi = GirlsBuiltinInstallApi(
      baseUri: widget.api.baseUri,
      client: _client,
    );
    _launchApi = HostedAuthoringLaunchApiClient(
      baseUri: widget.api.baseUri,
      client: _client,
    );
    _previewApi = HostedAuthoringPreviewApiClient(
      baseUri: widget.api.baseUri,
      client: _client,
    );
    _authoringTransport = HostedAuthoringApiClient(
      baseUri: widget.api.baseUri,
      client: _client,
    );
    _loadProjects();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  void _validateEditorApp() {
    final HostedGroupApp app = widget.editorApp;
    if (app.builtinId != novelEditorBuiltinId || app.sourceKind != 'builtin') {
      throw StateError('Novel Authoring page requires the installed novel-editor builtin.');
    }
  }

  Future<void> _loadProjects() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<GirlsNovelProjectSummary> summaries =
          await _projectsApi.listProjects(
        accessToken: widget.session.accessToken,
        groupId: widget.editorApp.groupId,
      );
      final List<GirlsNovelProject> projects = <GirlsNovelProject>[];
      for (final GirlsNovelProjectSummary summary in summaries) {
        final GirlsNovelProject project = await _projectsApi.loadProject(
          accessToken: widget.session.accessToken,
          contentId: summary.contentId,
        );
        if (project.summary.groupId != widget.editorApp.groupId ||
            project.summary.draftRevision != summary.draftRevision) {
          throw const FormatException(
            'Authoring project changed while the project list was loading.',
          );
        }
        projects.add(project);
      }
      if (mounted) setState(() => _projects = projects);
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForTitle() async {
    String value = '新しいノベル';
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('新しいノベルをつくる'),
        content: TextField(
          key: const Key('girls-novel-new-title'),
          controller: TextEditingController(text: value),
          maxLength: 100,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'タイトル'),
          onChanged: (String next) => value = next,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: const Text('つくる'),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject() async {
    if (_busy) return;
    final String? rawTitle = await _askForTitle();
    if (rawTitle == null || !mounted) return;
    final String title = rawTitle.trim();
    if (title.isEmpty || title.length > 100) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GirlsNovelProjectSummary created =
          await _projectsApi.createProject(
        accessToken: widget.session.accessToken,
        groupId: widget.editorApp.groupId,
        title: title,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _openEditor(created.contentId, title);
      if (mounted) await _loadProjects();
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor(String contentId, String title) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedAuthoringLaunchGrant launch = await _launchApi.createLaunch(
        accessToken: widget.session.accessToken,
        contentId: contentId,
        editorAppId: widget.editorApp.appId,
      );
      if (launch.contentFormat != minappNovelContentFormat ||
          !launch.allowedOperations.contains('load') ||
          !launch.allowedOperations.contains('save_document') ||
          !launch.allowedOperations.contains('publish_request')) {
        throw const FormatException(
          'Novel Editor launch returned an incompatible Authoring capability.',
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.authoring(
            title: '$title（編集）',
            launch: launch,
            runtimeTransport: widget.api.runtimeClient,
            authoringTransport: _authoringTransport,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<HostedGroupApp?> _resolveNovelPlayer() async {
    final List<HostedGroupApp> groupApps = await widget.api.listGroupApps(
      accessToken: widget.session.accessToken,
      groupId: widget.editorApp.groupId,
    );
    final List<HostedGroupApp> players = groupApps
        .where(
          (HostedGroupApp app) =>
              app.sourceKind == 'builtin' &&
              app.builtinId == novelPlayerBuiltinId,
        )
        .toList(growable: false);
    if (players.length > 1) {
      throw const FormatException(
        'The Novel Player builtin is installed more than once in this group.',
      );
    }
    if (players.length == 1) return players.single;
    if (!mounted) return null;

    final bool? install = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('プレビュー用プレイヤーを追加する？'),
        content: const Text(
          '下書きを実際のノベル画面で確認するには、公式プレイヤー「ひみつの放課後」がこのグループに必要です。追加してプレビューしますか？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            key: const Key('girls-novel-install-player-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('追加してプレビュー'),
          ),
        ],
      ),
    );
    if (install != true || !mounted) return null;

    return _builtinInstallApi.installNovelPlayer(
      accessToken: widget.session.accessToken,
      groupId: widget.editorApp.groupId,
    );
  }

  Future<void> _previewProject(GirlsNovelProject project) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedGroupApp? player = await _resolveNovelPlayer();
      if (player == null) return;
      final HostedAuthoringPreviewGrant preview = await _previewApi.createPreview(
        accessToken: widget.session.accessToken,
        contentId: project.summary.contentId,
        playerAppId: player.appId,
        expectedRevision: project.summary.draftRevision,
      );
      if (preview.contentFormat != minappNovelContentFormat) {
        throw const FormatException(
          'Novel preview returned an incompatible content format.',
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.session(
            title: '${project.title}（下書きプレビュー）',
            contentUri: preview.contentUri,
            runtimeToken: preview.runtimeToken,
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

  @override
  Widget build(BuildContext context) {
    final List<GirlsNovelProject>? projects = _projects;
    return Scaffold(
      backgroundColor: _novelSurface,
      appBar: AppBar(
        title: const Text('ノベル作品'),
        actions: <Widget>[
          IconButton(
            tooltip: '更新',
            onPressed: _busy ? null : _loadProjects,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('girls-novel-create'),
        onPressed: _busy ? null : _createProject,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新しくつくる'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProjects,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: <Widget>[
              const Text(
                'つくったノベル',
                style: TextStyle(
                  color: _novelInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '作品をタップすると編集、再生ボタンでは保存済みの下書きを本番と同じプレイヤーで確認できます。',
                style: TextStyle(color: _novelLavender, fontSize: 12),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('girls-novel-error'),
                  style: const TextStyle(
                    color: Color(0xFF9E3348),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (projects == null && _busy)
                const Center(child: CircularProgressIndicator())
              else if (projects == null)
                const Text('作品一覧を読み込めませんでした。')
              else if (projects.isEmpty)
                const _EmptyNovelProjects()
              else
                ...projects.map(
                  (GirlsNovelProject project) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        key: Key(
                          'girls-novel-project-${project.summary.contentId}',
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.auto_stories_rounded),
                        ),
                        title: Text(
                          project.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '下書き revision ${project.summary.draftRevision}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              key: Key(
                                'girls-novel-preview-${project.summary.contentId}',
                              ),
                              tooltip: '下書きをプレビュー',
                              onPressed:
                                  _busy ? null : () => _previewProject(project),
                              icon: const Icon(Icons.play_circle_outline_rounded),
                            ),
                            const Icon(Icons.edit_rounded),
                          ],
                        ),
                        enabled: !_busy,
                        onTap: _busy
                            ? null
                            : () => _openEditor(
                                  project.summary.contentId,
                                  project.title,
                                ),
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

class _EmptyNovelProjects extends StatelessWidget {
  const _EmptyNovelProjects();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(Icons.auto_stories_rounded, size: 42, color: _novelLavender),
            SizedBox(height: 10),
            Text(
              'まだ作品がないよ',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text('「新しくつくる」から最初のノベルを作れます。'),
          ],
        ),
      ),
    );
  }
}
