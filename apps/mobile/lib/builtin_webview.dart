import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool isBuiltInMicrophoneOnlyPermissionRequest(
  Set<WebViewPermissionResourceType> types,
) {
  return types.length == 1 &&
      types.contains(WebViewPermissionResourceType.microphone);
}

class BuiltInWebViewPage extends StatefulWidget {
  const BuiltInWebViewPage({
    required this.title,
    required this.assetPath,
    super.key,
  });

  final String title;
  final String assetPath;

  @override
  State<BuiltInWebViewPage> createState() => _BuiltInWebViewPageState();
}

class _BuiltInWebViewPageState extends State<BuiltInWebViewPage> {
  static const MethodChannel _hostPermissionChannel = MethodChannel(
    'jp.cloxs.min/host_permissions',
  );

  WebViewController? _controller;
  String? _error;
  int _progress = 0;
  bool _permissionPromptActive = false;

  static final RegExp _assetPathPattern = RegExp(
    r'^assets/builtin/[a-z0-9_-]+/index\.html$',
  );

  static const String _shoppingTownAssetPath =
      'assets/builtin/shopping_town/index.html';
  static const String _shoppingTownRulesAssetPath =
      'assets/builtin/shopping_town/rules.js';
  static const String _olHomeAssetPath =
      'assets/builtin/ol_home/index.html';
  static const String _olHomeEffectsAssetPath =
      'assets/builtin/ol_home/effects.js';

  @override
  void initState() {
    super.initState();
    _validateAssetPath(widget.assetPath);
    _prepareWebView();
  }

  static void _validateAssetPath(String assetPath) {
    if (!_assetPathPattern.hasMatch(assetPath)) {
      throw ArgumentError.value(
        assetPath,
        'assetPath',
        'Built-in app asset path is invalid.',
      );
    }
  }

  Future<String?> _loadExtraJavaScript() async {
    final String? extraAssetPath = switch (widget.assetPath) {
      _shoppingTownAssetPath => _shoppingTownRulesAssetPath,
      _olHomeAssetPath => _olHomeEffectsAssetPath,
      _ => null,
    };
    if (extraAssetPath == null) {
      return null;
    }

    final String script = await rootBundle.loadString(extraAssetPath);
    if (script.trim().isEmpty) {
      throw StateError('Built-in JavaScript asset is empty: $extraAssetPath');
    }
    return script;
  }

  Future<void> _prepareWebView() async {
    try {
      final String? extraJavaScript = await _loadExtraJavaScript();
      bool extraJavaScriptApplied = extraJavaScript == null;

      late final WebViewController controller;
      controller = WebViewController(
        onPermissionRequest: (WebViewPermissionRequest request) {
          unawaited(_handleWebPermissionRequest(request));
        },
      )
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() => _progress = progress);
              }
            },
            onPageFinished: (String _) async {
              if (extraJavaScriptApplied || extraJavaScript == null) {
                return;
              }
              try {
                await controller.runJavaScript(extraJavaScript);
                extraJavaScriptApplied = true;
              } catch (error) {
                if (!mounted) return;
                setState(
                  () => _error =
                      'ビルトインアプリの追加処理を読み込めませんでした: $error',
                );
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              final Uri? target = Uri.tryParse(request.url);
              if (target == null || !_isAllowedNavigation(target)) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        );

      // Built-in apps own their namespaced localStorage keys. Keep that storage
      // across launches so apps such as マイメモ帳 and みんあぷっち can persist data.
      await controller.clearCache();
      await controller.loadFlutterAsset(widget.assetPath);

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'ビルトインアプリを開けませんでした: $error');
    }
  }

  Future<void> _handleWebPermissionRequest(
    WebViewPermissionRequest request,
  ) async {
    if (!isBuiltInMicrophoneOnlyPermissionRequest(request.types)) {
      await request.deny();
      return;
    }
    if (!mounted || _permissionPromptActive) {
      await request.deny();
      return;
    }

    _permissionPromptActive = true;
    try {
      final bool approved = await _confirmMicrophoneAccess();
      if (!approved || !mounted) {
        await request.deny();
        return;
      }

      final bool hostPermissionGranted = await _requestHostMicrophonePermission();
      if (!hostPermissionGranted) {
        await request.deny();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('マイクの使用が許可されていないため、録音できません。'),
            ),
          );
        }
        return;
      }

      await request.grant();
    } catch (error) {
      try {
        await request.deny();
      } catch (_) {
        // Preserve the original permission-handling failure below.
      }
      if (mounted) {
        setState(() => _error = 'マイクの許可処理に失敗しました: $error');
      }
    } finally {
      _permissionPromptActive = false;
    }
  }

  Future<bool> _confirmMicrophoneAccess() async {
    final bool? approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('🎤 マイクを使いますか？'),
        content: Text(
          '「${widget.title}」が録音のためにマイクを使おうとしています。\n\n'
          '許可した場合だけ、このアプリからマイクを利用できます。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('許可しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('マイクを許可'),
          ),
        ],
      ),
    );
    return approved == true;
  }

  Future<bool> _requestHostMicrophonePermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final bool? granted = await _hostPermissionChannel.invokeMethod<bool>(
          'requestMicrophonePermission',
        );
        if (granted == null) {
          throw StateError(
            'Android microphone permission channel returned null.',
          );
        }
        return granted;
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  bool _isAllowedNavigation(Uri target) {
    if (target.scheme != 'file' || target.userInfo.isNotEmpty) {
      return false;
    }
    return target.path.endsWith('/flutter_assets/${widget.assetPath}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : _controller == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: <Widget>[
                      WebViewWidget(controller: _controller!),
                      if (_progress < 100)
                        LinearProgressIndicator(value: _progress / 100),
                    ],
                  ),
      ),
    );
  }
}
