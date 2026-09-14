import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'hosted_app_webview.dart';
import 'hosted_authoring_bridge.dart';
import 'hosted_authoring_contract_api.dart';
import 'hosted_authoring_launch_client.dart';
import 'hosted_authoring_preview_bridge.dart';
import 'hosted_authoring_preview_client.dart';
import 'hosted_authoring_projects_api.dart';
import 'hosted_authoring_resolver.dart';
import 'hosted_runtime_bridge.dart';

typedef HostedAuthoringErrorMessage = String Function(Object error);
typedef HostedAuthoringProjectTitle = String Function(
  HostedAuthoringProject project,
);
typedef HostedAuthoringInstallPlayer = Future<String?> Function(
  BuildContext context,
);

class HostedAuthoringProjectDefinition {
  const HostedAuthoringProjectDefinition({
    required this.contentFormat,
    required this.pageTitle,
    required this.collectionTitle,
    required this.emptyTitle,
    required this.emptyBody,
    this.projectIcon = Icons.edit_note_rounded,
    this.installCompatiblePlayer,
    this.projectTitle,
  });

  final String contentFormat;
  final String pageTitle;
  final String collectionTitle;
  final String emptyTitle;
  final String emptyBody;
  final IconData projectIcon;
  final HostedAuthoringInstallPlayer? installCompatiblePlayer;
  final HostedAuthoringProjectTitle? projectTitle;
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

  List<HostedAuthoringProjectSummary>? _projects;
  Map<String, String> _projectTitles = const <String, String>{};
  bool _busy = false;
  String? _error;

  bool get _isNovel => widget.definition.contentFormat == 'minapp/novel@1';

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

      final List<HostedAuthoringProjectSummary> projects =
          await _projectsApi.listProjects(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        contentFormat: widget.definition.contentFormat,
      );
      final Map<String, String> titles = <String, String>{};
      final HostedAuthoringProjectTitle? projectTitle =
          widget.definition.projectTitle;
      if (projectTitle != null) {
        for (final HostedAuthoringProjectSummary summary in projects) {
          final HostedAuthoringProject project = await _projectsApi.loadProject(
            accessToken: widget.accessToken,
            contentId: summary.contentId,
          );
          if (project.summary.contentId != summary.contentId ||
              project.summary.groupId != widget.groupId ||
              project.summary.contentFormat != widget.definition.contentFormat) {
            throw const FormatException(
              'Authoring project title lookup changed the requested scope.',
            );
          }
          final String title = projectTitle(project);
          if (title.isEmpty || title != title.trim() || title.length > 80) {
            throw const FormatException(
              'Authoring project title must be a trimmed non-empty string up to 80 characters.',
            );
          }
          titles[summary.contentId] = title;
        }
      }
      if (mounted) {
        setState(() {
          _projects = projects;
          _projectTitles = Map<String, String>.unmodifiable(titles);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createProject() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedAuthoringProjectSummary created =
          await _projectsApi.createProject(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        contentFormat: widget.definition.contentFormat,
        document: <String, Object?>{},
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _openEditor(created.contentId);
      if (mounted) await _loadProjects();
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor(String contentId) async {
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
          !launch.allowedOperations.contains('preview_request') ||
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
            title: _isNovel
                ? widget.definition.pageTitle
                : '${widget.definition.pageTitle}（編集）',
            launch: launch,
            runtimeTransport: widget.runtimeTransport,
            authoringTransport: _authoringTransport,
            authoringPreviewHost: (int expectedRevision) =>
                _previewFromEditor(contentId, expectedRevision),
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
        title: const Text('どのプレイヤーで再生する？'),
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

  Future<HostedAuthoringPreviewGrant?> _createPreview({
    required String contentId,
    required int expectedRevision,
  }) async {
    final HostedAuthoringAppContract? player = await _resolvePlayer();
    if (player == null) return null;
    final HostedAuthoringPreviewGrant preview = await _previewApi.createPreview(
      accessToken: widget.accessToken,
      contentId: contentId,
      playerAppId: player.appId,
      expectedRevision: expectedRevision,
    );
    if (preview.contentFormat != widget.definition.contentFormat) {
      throw const FormatException(
        'Preview returned an incompatible content format.',
      );
    }
    return preview;
  }

  Future<void> _showPreview(HostedAuthoringPreviewGrant preview) async {
    if (!mounted) {
      throw const HostedAuthoringPreviewHostException(
        statusCode: 409,
        code: 'authoring_host_unavailable',
        message: 'The Authoring Host is no longer active.',
      );
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedAppWebViewPage.session(
          title: '${widget.definition.pageTitle}（下書きを再生）',
          contentUri: preview.contentUri,
          runtimeToken: preview.runtimeToken,
          runtimeTransport: widget.runtimeTransport,
        ),
      ),
    );
  }

  Future<Object?> _previewFromEditor(
    String contentId,
    int expectedRevision,
  ) async {
    try {
      final HostedAuthoringPreviewGrant? preview = await _createPreview(
        contentId: contentId,
        expectedRevision: expectedRevision,
      );
      if (preview == null) return null;
      await _showPreview(preview);
      return <String, Object?>{
        'content_format': preview.contentFormat,
        'draft_revision': preview.draftRevision,
        'player_app_id': preview.playerAppId,
      };
    } on StateError catch (error) {
      throw HostedAuthoringPreviewHostException(
        statusCode: 409,
        code: 'authoring_player_unavailable',
        message: error.toString(),
      );
    }
  }

  Future<void> _previewProject(HostedAuthoringProjectSummary project) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final HostedAuthoringPreviewGrant? preview = await _createPreview(
        contentId: project.contentId,
        expectedRevision: project.draftRevision,
      );
      if (preview == null) return;
      if (!mounted) return;
      setState(() => _busy = false);
      await _showPreview(preview);
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProject(HostedAuthoringProjectSummary project) async {
    if (_busy || !mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('この作品を削除しますか？'),
        content: const Text(
          '公開済みの場合は公開アプリも削除されます。この操作は取り消せません。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('hosted-authoring-delete-confirm'),
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
      await _projectsApi.deleteProject(
        accessToken: widget.accessToken,
        contentId: project.contentId,
      );
      if (!mounted) return;
      setState(() {
        _projects = _projects
            ?.where(
              (HostedAuthoringProjectSummary item) =>
                  item.contentId != project.contentId,
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostedAuthoringProjectSummary>? projects = _projects;
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
              if (_isNovel)
                _NovelProjectsIntro(title: widget.definition.collectionTitle)
              else ...<Widget>[
                Text(
                  widget.definition.collectionTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '作品をタップすると編集できます。再生ボタンでは、保存済みの下書きをみんアプ内の対応プレイヤーで開きます。',
                ),
              ],
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
                  (HostedAuthoringProjectSummary project) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        key: Key(
                          'hosted-authoring-project-${project.contentId}',
                        ),
                        leading: CircleAvatar(
                          child: Icon(widget.definition.projectIcon),
                        ),
                        title: Text(
                          _projectTitles[project.contentId] ?? '作品',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '下書き revision ${project.draftRevision}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              key: Key(
                                'hosted-authoring-preview-${project.contentId}',
                              ),
                              tooltip: '下書きを再生',
                              onPressed:
                                  _busy ? null : () => _previewProject(project),
                              icon: const Icon(Icons.play_circle_outline_rounded),
                            ),
                            IconButton(
                              key: Key(
                                'hosted-authoring-delete-${project.contentId}',
                              ),
                              tooltip: '作品を削除',
                              onPressed:
                                  _busy ? null : () => _deleteProject(project),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                            const Icon(Icons.edit_rounded),
                          ],
                        ),
                        enabled: !_busy,
                        onTap: _busy ? null : () => _openEditor(project.contentId),
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

class _NovelProjectsIntro extends StatelessWidget {
  const _NovelProjectsIntro({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFFBFD), Color(0xFFF8F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEBCFDC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12745B9E),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF4E9FB),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Color(0xFF745B9E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF604943),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '作品をタップして編集できます',
                  style: TextStyle(
                    color: Color(0xFF8C7893),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            '✦',
            style: TextStyle(color: Color(0xFFEFA5C0), fontSize: 18),
          ),
        ],
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