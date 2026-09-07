import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'hosted_app_webview.dart';
import 'hosted_authoring_bridge.dart';
import 'hosted_authoring_contract_api.dart';
import 'hosted_authoring_launch_client.dart';
import 'hosted_authoring_preview_client.dart';
import 'hosted_authoring_projects_api.dart';
import 'hosted_authoring_resolver.dart';
import 'hosted_runtime_bridge.dart';

typedef HostedAuthoringProjectTitle = String Function(
  Map<String, Object?> document,
);
typedef HostedAuthoringInitialDocument = Map<String, Object?> Function(
  String title,
);
typedef HostedAuthoringErrorMessage = String Function(Object error);
typedef HostedAuthoringInstallPlayer = Future<String?> Function(
  BuildContext context,
);

class HostedAuthoringProjectDefinition {
  const HostedAuthoringProjectDefinition({
    required this.contentFormat,
    required this.pageTitle,
    required this.collectionTitle,
    required this.defaultProjectTitle,
    required this.createDialogTitle,
    required this.emptyTitle,
    required this.emptyBody,
    required this.projectTitle,
    required this.initialDocument,
    this.projectIcon = Icons.edit_note_rounded,
    this.installCompatiblePlayer,
  });

  final String contentFormat;
  final String pageTitle;
  final String collectionTitle;
  final String defaultProjectTitle;
  final String createDialogTitle;
  final String emptyTitle;
  final String emptyBody;
  final IconData projectIcon;
  final HostedAuthoringProjectTitle projectTitle;
  final HostedAuthoringInitialDocument initialDocument;
  final HostedAuthoringInstallPlayer? installCompatiblePlayer;
}

class HostedAuthoringProjectsPage extends StatefulWidget {
  const HostedAuthoringProjectsPage({
    required this.baseUri,
    required this.accessToken,
    required this.groupId,
    required this.editorAppId,
    required this.runtimeTransport,
    required this.definition,
    required this.errorMessage,
    super.key,
  });

  final Uri baseUri;
  final String accessToken;
  final String groupId;
  final String editorAppId;
  final HostedRuntimeTransport runtimeTransport;
  final HostedAuthoringProjectDefinition definition;
  final HostedAuthoringErrorMessage errorMessage;

  @override
  State<HostedAuthoringProjectsPage> createState() =>
      _HostedAuthoringProjectsPageState();
}

class _HostedAuthoringProjectsPageState
    extends State<HostedAuthoringProjectsPage> {
  late final http.Client _client;
  late final HostedAuthoringProjectsApi _projectsApi;
  late final HostedAuthoringContractApi _contractApi;
  late final HostedAuthoringLaunchApiClient _launchApi;
  late final HostedAuthoringPreviewApiClient _previewApi;
  late final HostedAuthoringApiClient _authoringTransport;

  List<HostedAuthoringProject>? _projects;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _projectsApi = HostedAuthoringProjectsApi(
      baseUri: widget.baseUri,
      client: _client,
    );
    _contractApi = HostedAuthoringContractApi(
      baseUri: widget.baseUri,
      client: _client,
    );
    _launchApi = HostedAuthoringLaunchApiClient(
      baseUri: widget.baseUri,
      client: _client,
    );
    _previewApi = HostedAuthoringPreviewApiClient(
      baseUri: widget.baseUri,
      client: _client,
    );
    _authoringTransport = HostedAuthoringApiClient(
      baseUri: widget.baseUri,
      client: _client,
    );
    _loadProjects();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<List<HostedAuthoringAppContract>> _authoringContracts() {
    return _contractApi.listApps(
      accessToken: widget.accessToken,
      groupId: widget.groupId,
    );
  }

  Future<void> _loadProjects() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<HostedAuthoringAppContract> contracts =
          await _authoringContracts();
      HostedAuthoringResolver.requireEditor(
        apps: contracts,
        appId: widget.editorAppId,
        contentFormat: widget.definition.contentFormat,
      );

      final List<HostedAuthoringProjectSummary> summaries =
          await _projectsApi.listProjects(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        contentFormat: widget.definition.contentFormat,
      );
      final List<HostedAuthoringProject> projects = <HostedAuthoringProject>[];
      for (final HostedAuthoringProjectSummary summary in summaries) {
        final HostedAuthoringProject project = await _projectsApi.loadProject(
          accessToken: widget.accessToken,
          contentId: summary.contentId,
        );
        if (project.summary.groupId != widget.groupId ||
            project.summary.contentFormat != widget.definition.contentFormat ||
            project.summary.draftRevision != summary.draftRevision) {
          throw const FormatException(
            'Authoring project changed while the project list was loading.',
          );
        }
        widget.definition.projectTitle(project.document);
        projects.add(project);
      }
      if (mounted) setState(() => _projects = projects);
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForTitle() async {
    String value = widget.definition.defaultProjectTitle;
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(widget.definition.createDialogTitle),
        content: TextFormField(
          key: const Key('hosted-authoring-new-title'),
          initialValue: value,
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
      final Map<String, Object?> document =
          widget.definition.initialDocument(title);
      final HostedAuthoringProjectSummary created =
          await _projectsApi.createProject(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        contentFormat: widget.definition.contentFormat,
        document: document,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _openEditor(created.contentId, title);
      if (mounted) await _loadProjects();
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
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
        accessToken: widget.accessToken,
        contentId: contentId,
        editorAppId: widget.editorAppId,
      );
      if (launch.contentFormat != widget.definition.contentFormat ||
          !launch.allowedOperations.contains('load') ||
          !launch.allowedOperations.contains('save_document') ||
          !launch.allowedOperations.contains('publish_request')) {
        throw const FormatException(
          'Editor launch returned an incompatible Authoring capability.',
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.authoring(
            title: '$title（編集）',
            launch: launch,
            runtimeTransport: widget.runtimeTransport,
            authoringTransport: _authoringTransport,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<HostedAuthoringAppContract?> _chooseCompatiblePlayer(
    List<HostedAuthoringAppContract> players,
  ) async {
    if (players.isEmpty) return null;
    if (players.length == 1) return players.single;
    if (!mounted) return null;

    return showDialog<HostedAuthoringAppContract>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('どのプレイヤーで確認する？'),
        children: players
            .map(
              (HostedAuthoringAppContract player) => SimpleDialogOption(
                key: Key('hosted-authoring-player-${player.appId}'),
                onPressed: () => Navigator.of(dialogContext).pop(player),
                child: Text(player.title),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<HostedAuthoringAppContract?> _resolvePlayer() async {
    List<HostedAuthoringAppContract> contracts = await _authoringContracts();
    List<HostedAuthoringAppContract> players = HostedAuthoringResolver.playersFor(
      contracts,
      widget.definition.contentFormat,
    );
    final HostedAuthoringAppContract? selected =
        await _chooseCompatiblePlayer(players);
    if (selected != null || players.isNotEmpty) return selected;

    final HostedAuthoringInstallPlayer? install =
        widget.definition.installCompatiblePlayer;
    if (install == null || !mounted) {
      throw StateError(
        'No installed Player accepts ${widget.definition.contentFormat}.',
      );
    }
    final String? installedAppId = await install(context);
    if (installedAppId == null) return null;

    contracts = await _authoringContracts();
    players = HostedAuthoringResolver.playersFor(
      contracts,
      widget.definition.contentFormat,
    );
    final List<HostedAuthoringAppContract> installedMatches = players
        .where((HostedAuthoringAppContract player) => player.appId == installedAppId)
        .toList(growable: false);
    if (installedMatches.length != 1) {
      throw const FormatException(
        'Installed Player did not appear exactly once with the required accepts contract.',
      );
    }
    return installedMatches.single;
  }

  Future<void> _previewProject(HostedAuthoringProject project) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedAuthoringAppContract? player = await _resolvePlayer();
      if (player == null) return;
      final HostedAuthoringPreviewGrant preview = await _previewApi.createPreview(
        accessToken: widget.accessToken,
        contentId: project.summary.contentId,
        playerAppId: player.appId,
        expectedRevision: project.summary.draftRevision,
      );
      if (preview.contentFormat != widget.definition.contentFormat) {
        throw const FormatException(
          'Preview returned an incompatible content format.',
        );
      }
      if (!mounted) return;
      final String title = widget.definition.projectTitle(project.document);
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.session(
            title: '$title（下書きプレビュー）',
            contentUri: preview.contentUri,
            runtimeToken: preview.runtimeToken,
            runtimeTransport: widget.runtimeTransport,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedAuthoringProject>? projects = _projects;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.definition.pageTitle),
        actions: <Widget>[
          IconButton(
            tooltip: '更新',
            onPressed: _busy ? null : _loadProjects,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('hosted-authoring-create'),
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
              Text(
                widget.definition.collectionTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '作品をタップすると編集、再生ボタンでは保存済みの下書きを対応プレイヤーで確認できます。',
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('hosted-authoring-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
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
                _EmptyProjects(
                  title: widget.definition.emptyTitle,
                  body: widget.definition.emptyBody,
                )
              else
                ...projects.map(
                  (HostedAuthoringProject project) {
                    final String title =
                        widget.definition.projectTitle(project.document);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          key: Key(
                            'hosted-authoring-project-${project.summary.contentId}',
                          ),
                          leading: CircleAvatar(
                            child: Icon(widget.definition.projectIcon),
                          ),
                          title: Text(
                            title,
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
                                  'hosted-authoring-preview-${project.summary.contentId}',
                                ),
                                tooltip: '下書きをプレビュー',
                                onPressed: _busy
                                    ? null
                                    : () => _previewProject(project),
                                icon: const Icon(
                                  Icons.play_circle_outline_rounded,
                                ),
                              ),
                              const Icon(Icons.edit_rounded),
                            ],
                          ),
                          enabled: !_busy,
                          onTap: _busy
                              ? null
                              : () => _openEditor(
                                    project.summary.contentId,
                                    title,
                                  ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            const Icon(Icons.edit_note_rounded, size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
