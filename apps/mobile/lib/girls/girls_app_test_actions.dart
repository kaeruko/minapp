import 'package:flutter/material.dart';

import '../hosted_app_webview.dart';
import '../hosted_authoring_contract_api.dart';
import '../hosted_authoring_editor_action.dart';
import 'api.dart';
import 'girls_errors.dart';
import 'girls_app_management_api.dart';
import 'girls_app_preview_api.dart';
import 'girls_app_source_editor_page.dart';
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
    this.detailLayout = false,
    this.disabled = false,
    super.key,
  });

  final HostedGirlsApi api;
  final AuthenticatedSession session;
  final ManagedGirlsAppDetail detail;
  final HostedAuthoringContractApi? authoringContractApi;
  final bool detailLayout;
  final bool disabled;

  @override
  State<GirlsAppTestActions> createState() => _GirlsAppTestActionsState();
}

class _GirlsAppTestActionsState extends State<GirlsAppTestActions> {
  late final GirlsAppPreviewApi _previewApi;
  late final GirlsBuiltinInstallApi _builtinInstallApi;
  late final GirlsAppManagementApi _managementApi;
  late final HostedAuthoringContractApi _contractApi;
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
    _previewApi = GirlsAppPreviewApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _builtinInstallApi = GirlsBuiltinInstallApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _managementApi = GirlsAppManagementApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    _contractApi = HostedAuthoringContractApi(
        baseUri: widget.api.baseUri, client: widget.api.httpClient);
    if (_isNovelEditor) {
      _novelSetupBusy = true;
      _prepareNovelEditor(initial: true);
    }
  }

  @override
  void dispose() {
    _previewApi.close();
    _builtinInstallApi.close();
    _managementApi.close();
    _contractApi.close();
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
        _novelSetupError = girlsMessageFor(error);
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
      titleSuffix: 'プレビュー',
    );
  }

  Future<void> _editSource() async {
    final ManagedGirlsApp app = widget.detail.summary;
    final int? sourceRevision = app.sourceRevision;
    if (!app.app.editable || sourceRevision == null) {
      throw StateError('Editable source revision is not available.');
    }

    final int? revision = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (BuildContext context) => GirlsAppSourceEditorPage(
          api: _managementApi,
          accessToken: widget.session.accessToken,
          groupId: app.app.groupId,
          appId: app.app.appId,
          title: app.app.title,
          expectedRevision: sourceRevision,
        ),
      ),
    );
    if (revision == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('コードを保存しました。編集版を更新しました。')),
    );

    // The detail page owns its loaded revision. Returning to the app list makes
    // that page discard the stale revision before the user can publish it.
    Navigator.of(context).pop();
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
      if (mounted) setState(() => _error = girlsMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Widget _runtimeActions() {
    if (widget.detailLayout) return _detailActions();
    final ManagedGirlsAppDetail detail = widget.detail;
    final int? sourceRevision = detail.summary.sourceRevision;
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
          onPressed:
              _busy || sourceRevision == null ? null : _previewLatestRevision,
          icon: const Icon(Icons.preview_rounded),
          label: const Text('編集版をプレビュー'),
        ),
        if (detail.summary.app.editable && sourceRevision != null) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('girls-app-edit-code'),
            onPressed: _busy ? null : _editSource,
            icon: const Icon(Icons.code_rounded),
            label: const Text('コードを編集'),
          ),
        ],
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

  Widget _detailActions() {
    final app = widget.detail.summary;
    final disabled = _busy || widget.disabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('girls-app-preview-latest'),
          onPressed: disabled || app.sourceRevision == null
              ? null
              : _previewLatestRevision,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF2CDD5),
            foregroundColor: const Color(0xFF604943),
            minimumSize: const Size.fromHeight(52),
            textStyle:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          icon: const Icon(Icons.play_circle_fill_rounded,
              color: Color(0xFFB98295)),
          label: const Text('プレビュー'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: _testError)),
          ),
        if (app.app.editable && app.sourceRevision != null) ...[
          const SizedBox(height: 14),
          TextButton.icon(
            key: const Key('girls-app-edit-code'),
            onPressed: disabled ? null : _editSource,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF604943),
              minimumSize: const Size.fromHeight(48),
              textStyle:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            icon: const Icon(Icons.edit_outlined, color: Color(0xFFB98295)),
            label: const Text('アプリを編集'),
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
          onPressed: () => _prepareNovelEditor(),
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
      authoringContractApi: widget.authoringContractApi ?? _contractApi,
      errorMessage: girlsMessageFor,
      nonEditorChild: _runtimeActions(),
    );
  }
}
