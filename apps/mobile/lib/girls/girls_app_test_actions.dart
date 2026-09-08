import 'package:flutter/material.dart';

import '../hosted_app_webview.dart';
import '../hosted_authoring_contract_api.dart';
import '../hosted_authoring_editor_action.dart';
import 'api.dart';
import 'girls_app_core.dart' as core;
import 'girls_app_management_api.dart';
import 'girls_app_preview_api.dart';
import 'girls_builtin_install_api.dart';
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
  late final GirlsBuiltinInstallApi _builtinInstallApi;
  bool _busy = false;
  String? _error;
  bool _novelSetupBusy = false;
  bool _novelSetupReady = false;
  String? _novelSetupError;

  bool get _isNovelEditor {
    final HostedGroupApp app = widget.detail.summary.app;
    return app.sourceKind == 'builtin' && app.builtinId == novelEditorBuiltinId;
  }

  @override
  void initState() {
    super.initState();
    _previewApi = GirlsAppPreviewApi(baseUri: widget.api.baseUri);
    _builtinInstallApi = GirlsBuiltinInstallApi(baseUri: widget.api.baseUri);
    if (_isNovelEditor) {
      _novelSetupBusy = true;
      _prepareNovelEditor(initial: true);
    }
  }

  @override
  void dispose() {
    _previewApi.close();
    _builtinInstallApi.close();
    super.dispose();
  }

  Future<void> _prepareNovelEditor({bool initial = false}) async {
    if (!_isNovelEditor) return;
    if (!initial) {
      setState(() {
        _novelSetupBusy = true;
        _novelSetupReady = false;
        _novelSetupError = null;
      });
    }
    final HostedGroupApp app = widget.detail.summary.app;
    try {
      await _builtinInstallApi.ensureNovelPlayer(
        accessToken: widget.session.accessToken,
        groupId: app.groupId,
      );
      if (!mounted) return;
      setState(() {
        _novelSetupReady = true;
        _novelSetupError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _novelSetupReady = false;
        _novelSetupError = core.girlsMessageFor(error);
      });
    } finally {
      if (mounted) setState(() => _novelSetupBusy = false);
    }
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
      if (mounted) setState(() => _error = core.girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Widget _runtimeActions() {
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

  Widget _novelSetupState() {
    if (_novelSetupBusy) {
      return const Column(
        children: <Widget>[
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 8),
          Text(
            'Preview用Playerを準備しています…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _testLavender,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _novelSetupError ?? 'Preview用Playerを準備できませんでした。',
          key: const Key('girls-novel-player-setup-error'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _testError,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('girls-novel-player-setup-retry'),
          onPressed: _prepareNovelEditor,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Playerを準備しなおす'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final HostedGroupApp app = widget.detail.summary.app;
    if (_isNovelEditor && !_novelSetupReady) {
      return _novelSetupState();
    }
    return HostedAuthoringEditorAction(
      baseUri: widget.api.baseUri,
      accessToken: widget.session.accessToken,
      groupId: app.groupId,
      editorAppId: app.appId,
      runtimeTransport: widget.api.runtimeClient,
      authoringContractApi: widget.authoringContractApi,
      errorMessage: core.girlsMessageFor,
      nonEditorChild: _runtimeActions(),
    );
  }
}
