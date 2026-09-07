import 'package:flutter/material.dart';

import '../hosted_app_webview.dart';
import '../hosted_authoring_contract_api.dart';
import '../hosted_authoring_projects_page.dart';
import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_app_management_api.dart';
import 'girls_app_preview_api.dart';
import 'hosted_girls_api.dart';

const Color _testLavender = Color(0xFF745B9E);
const Color _testError = Color(0xFF9E3348);

class GirlsAppTestActions extends StatefulWidget {
  const GirlsAppTestActions({
    required this.api,
    required this.session,
    required this.detail,
    this.authoringContractApi,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final ManagedGirlsAppDetail detail;
  final HostedAuthoringContractApi? authoringContractApi;

  @override
  State<GirlsAppTestActions> createState() => _GirlsAppTestActionsState();
}

class _GirlsAppTestActionsState extends State<GirlsAppTestActions> {
  late final GirlsAppPreviewApi _previewApi;
  late final HostedAuthoringContractApi _authoringContractApi;
  late final bool _ownsAuthoringContractApi;
  List<String>? _editorFormats;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _previewApi = GirlsAppPreviewApi(baseUri: widget.api.baseUri);
    final HostedAuthoringContractApi? supplied = widget.authoringContractApi;
    _ownsAuthoringContractApi = supplied == null;
    _authoringContractApi = supplied ??
        HostedAuthoringContractApi(
          baseUri: widget.api.baseUri,
        );
    _loadAuthoringContract();
  }

  @override
  void dispose() {
    _previewApi.close();
    if (_ownsAuthoringContractApi) _authoringContractApi.close();
    super.dispose();
  }

  Future<void> _loadAuthoringContract() async {
    try {
      final HostedGroupApp app = widget.detail.summary.app;
      final List<HostedAuthoringAppContract> contracts =
          await _authoringContractApi.listApps(
        accessToken: widget.session.accessToken,
        groupId: app.groupId,
      );
      final List<HostedAuthoringAppContract> matches = contracts
          .where((HostedAuthoringAppContract contract) => contract.appId == app.appId)
          .toList(growable: false);
      if (matches.length > 1) {
        throw const FormatException(
          'Authoring contract list contains duplicate app_id entries.',
        );
      }
      if (!mounted) return;
      setState(() {
        _editorFormats = matches.isEmpty
            ? const <String>[]
            : List<String>.unmodifiable(matches.single.edits);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = core.girlsMessageFor(error));
    }
  }

  Future<String?> _chooseEditorFormat(List<String> formats) async {
    if (formats.isEmpty) return null;
    if (formats.length == 1) return formats.single;
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('どの作品形式を編集する？'),
        children: formats
            .map(
              (String format) => SimpleDialogOption(
                key: Key('girls-authoring-format-$format'),
                onPressed: () => Navigator.of(dialogContext).pop(format),
                child: Text(format),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _openAuthoringProjects() async {
    if (_busy) return;
    final List<String> formats = _editorFormats ?? const <String>[];
    final String? contentFormat = await _chooseEditorFormat(formats);
    if (contentFormat == null || !mounted) return;
    final HostedGroupApp app = widget.detail.summary.app;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => HostedAuthoringProjectsPage(
          baseUri: widget.api.baseUri,
          accessToken: widget.session.accessToken,
          groupId: app.groupId,
          editorAppId: app.appId,
          runtimeTransport: widget.api.runtimeClient,
          definition: HostedAuthoringProjectDefinition(
            contentFormat: contentFormat,
            pageTitle: '作品編集',
            collectionTitle: 'つくった作品',
            emptyTitle: 'まだ作品がありません',
            emptyBody: '「新しくつくる」からはじめよう。',
          ),
          errorMessage: core.girlsMessageFor,
        ),
      ),
    );
  }

  Future<void> _tryPublished() async {
    final ManagedGirlsApp app = widget.detail.summary;
    if (app.app.publishedVersion == null) return;
    await _openSession(
      create: () => _previewApi.createPublishedTest(
        accessToken: widget.session.accessToken,
        groupId: app.app.groupId,
        appId: app.app.appId,
      ),
      titleSuffix: '公開版テスト',
    );
  }

  Future<void> _previewLatestRevision() async {
    final ManagedGirlsApp app = widget.detail.summary;
    if (app.sourceRevision == null) return;
    await _openSession(
      create: () => _previewApi.createDraftPreview(
        accessToken: widget.session.accessToken,
        groupId: app.app.groupId,
        appId: app.app.appId,
      ),
      titleSuffix: '更新版プレビュー',
    );
  }

  Future<void> _openSession({
    required Future<GirlsAppTestSession> Function() create,
    required String titleSuffix,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GirlsAppTestSession launch = await create();
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => HostedAppWebViewPage.session(
            title: '${widget.detail.summary.app.title}（$titleSuffix）',
            contentUri: launch.contentUri,
            runtimeToken: launch.runtimeToken,
            runtimeTransport: widget.api.runtimeClient,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = core.girlsMessageFor(error));
      }
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String>? editorFormats = _editorFormats;
    if (editorFormats != null && editorFormats.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('girls-authoring-open-projects'),
            onPressed: _busy ? null : _openAuthoringProjects,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('作品を編集'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _testError,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      );
    }

    final ManagedGirlsAppDetail detail = widget.detail;
    final int? sourceRevision = detail.summary.sourceRevision;
    final int? latestPublishedRevision = detail.publishedHistory.isEmpty
        ? null
        : detail.publishedHistory.first.sourceRevision;
    final bool hasUnpublishedUpdate = sourceRevision != null &&
        sourceRevision != latestPublishedRevision;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.tonalIcon(
          key: const Key('girls-app-try-published'),
          onPressed: _busy || detail.summary.app.publishedVersion == null
              ? null
              : _tryPublished,
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: const Text('公開中のアプリを試す'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('girls-app-preview-latest'),
          onPressed: _busy || sourceRevision == null
              ? null
              : _previewLatestRevision,
          icon: const Icon(Icons.preview_rounded),
          label: Text(
            hasUnpublishedUpdate ? '更新版をプレビュー' : '最新revisionをプレビュー',
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          '自分で試した回数は「遊ばれた回数」には加算されません。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _testLavender,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _testError,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
