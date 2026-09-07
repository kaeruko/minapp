import 'package:flutter/material.dart';

import 'hosted_authoring_contract_api.dart';
import 'hosted_authoring_projects_page.dart';
import 'hosted_runtime_bridge.dart';

Future<void> openHostedAuthoringProjects({
  required BuildContext context,
  required Uri baseUri,
  required String accessToken,
  required String groupId,
  required String editorAppId,
  required HostedRuntimeTransport runtimeTransport,
  required List<String> editorFormats,
  required HostedAuthoringErrorMessage errorMessage,
  required String pageTitle,
  required String collectionTitle,
  required String emptyTitle,
  required String emptyBody,
}) async {
  if (editorFormats.isEmpty) {
    throw StateError('Selected app is not an Authoring Editor.');
  }

  String? contentFormat;
  if (editorFormats.length == 1) {
    contentFormat = editorFormats.single;
  } else {
    contentFormat = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('どの作品形式を編集する？'),
        children: editorFormats
            .map(
              (String format) => SimpleDialogOption(
                key: Key('hosted-authoring-format-$format'),
                onPressed: () => Navigator.of(dialogContext).pop(format),
                child: Text(format),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
  if (contentFormat == null || !context.mounted) return;

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => HostedAuthoringProjectsPage(
        baseUri: baseUri,
        accessToken: accessToken,
        groupId: groupId,
        editorAppId: editorAppId,
        runtimeTransport: runtimeTransport,
        definition: HostedAuthoringProjectDefinition(
          contentFormat: contentFormat!,
          pageTitle: pageTitle,
          collectionTitle: collectionTitle,
          emptyTitle: emptyTitle,
          emptyBody: emptyBody,
        ),
        errorMessage: errorMessage,
      ),
    ),
  );
}

class HostedAuthoringEditorAction extends StatefulWidget {
  const HostedAuthoringEditorAction({
    required this.baseUri,
    required this.accessToken,
    required this.groupId,
    required this.editorAppId,
    required this.runtimeTransport,
    required this.errorMessage,
    required this.nonEditorChild,
    this.authoringContractApi,
    this.buttonLabel = '作品を編集',
    this.pageTitle = '作品編集',
    this.collectionTitle = 'つくった作品',
    this.emptyTitle = 'まだ作品がありません',
    this.emptyBody = '「新しくつくる」からはじめよう。',
    super.key,
  });

  final Uri baseUri;
  final String accessToken;
  final String groupId;
  final String editorAppId;
  final HostedRuntimeTransport runtimeTransport;
  final HostedAuthoringErrorMessage errorMessage;
  final Widget nonEditorChild;
  final HostedAuthoringContractApi? authoringContractApi;
  final String buttonLabel;
  final String pageTitle;
  final String collectionTitle;
  final String emptyTitle;
  final String emptyBody;

  @override
  State<HostedAuthoringEditorAction> createState() =>
      _HostedAuthoringEditorActionState();
}

class _HostedAuthoringEditorActionState
    extends State<HostedAuthoringEditorAction> {
  late final HostedAuthoringContractApi _contractApi;
  late final bool _ownsContractApi;
  List<String>? _editorFormats;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final HostedAuthoringContractApi? supplied = widget.authoringContractApi;
    _ownsContractApi = supplied == null;
    _contractApi = supplied ?? HostedAuthoringContractApi(baseUri: widget.baseUri);
    _loadContract();
  }

  @override
  void dispose() {
    if (_ownsContractApi) _contractApi.close();
    super.dispose();
  }

  Future<void> _loadContract() async {
    try {
      final List<HostedAuthoringAppContract> contracts =
          await _contractApi.listApps(
        accessToken: widget.accessToken,
        groupId: widget.groupId,
      );
      final List<HostedAuthoringAppContract> matches = contracts
          .where(
            (HostedAuthoringAppContract contract) =>
                contract.appId == widget.editorAppId,
          )
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
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _editorFormats = const <String>[];
        _error = widget.errorMessage(error);
      });
    }
  }

  Future<void> _openProjects() async {
    if (_busy) return;
    final List<String> formats = _editorFormats ?? const <String>[];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await openHostedAuthoringProjects(
        context: context,
        baseUri: widget.baseUri,
        accessToken: widget.accessToken,
        groupId: widget.groupId,
        editorAppId: widget.editorAppId,
        runtimeTransport: widget.runtimeTransport,
        editorFormats: formats,
        errorMessage: widget.errorMessage,
        pageTitle: widget.pageTitle,
        collectionTitle: widget.collectionTitle,
        emptyTitle: widget.emptyTitle,
        emptyBody: widget.emptyBody,
      );
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String>? formats = _editorFormats;
    final String? error = _error;
    if (formats == null || formats.isEmpty) {
      if (error == null) return widget.nonEditorChild;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          widget.nonEditorChild,
          const SizedBox(height: 7),
          Text(
            error,
            key: const Key('hosted-authoring-editor-action-error'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
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
        FilledButton.icon(
          key: const Key('hosted-authoring-open-projects'),
          onPressed: _busy ? null : _openProjects,
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(widget.buttonLabel),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            error,
            key: const Key('hosted-authoring-editor-action-error'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
