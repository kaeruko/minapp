import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'hosted_runtime_bridge.dart';

bool isHostedMicrophoneOnlyPermissionRequest(
  Set<WebViewPermissionResourceType> types,
) {
  return types.length == 1 &&
      types.contains(WebViewPermissionResourceType.microphone);
}

class HostedAppWebViewPage extends StatefulWidget {
  const HostedAppWebViewPage({
    required this.title,
    required this.launch,
    required this.runtimeTransport,
    super.key,
  });

  final String title;
  final HostedLaunchGrant launch;
  final HostedRuntimeTransport runtimeTransport;

  @override
  State<HostedAppWebViewPage> createState() => _HostedAppWebViewPageState();
}

class _HostedAppWebViewPageState extends State<HostedAppWebViewPage> {
  static const MethodChannel _hostPermissionChannel = MethodChannel(
    'jp.cloxs.min/host_permissions',
  );

  WebViewController? _controller;
  String? _error;
  int _progress = 0;
  bool _bridgeFailed = false;
  bool _permissionPromptActive = false;

  late final HostedContentNavigationPolicy _navigationPolicy;
  late final HostedBridgeSession _bridgeSession;
  final HostedBridgeDocumentInjector _injector = HostedBridgeDocumentInjector();

  @override
  void initState() {
    super.initState();
    _navigationPolicy = HostedContentNavigationPolicy(widget.launch.contentUri);
    _bridgeSession = HostedBridgeSession(
      transport: widget.runtimeTransport,
      runtimeToken: widget.launch.runtimeToken,
    );
    _prepareWebView();
  }

  Future<void> _prepareWebView() async {
    try {
      await WebViewCookieManager().clearCookies();
      final WebViewController controller = WebViewController(
        onPermissionRequest: (WebViewPermissionRequest request) {
          unawaited(_handleWebPermissionRequest(request));
        },
      )
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'MinAppNativeBridge',
          onMessageReceived: _onBridgeMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() => _progress = progress);
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              final Uri? target = Uri.tryParse(request.url);
              if (target == null || !_navigationPolicy.allows(target)) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageFinished: (String url) {
              _injectBridgeForFinishedDocument(url);
            },
          ),
        );
      await controller.clearLocalStorage();
      await controller.clearCache();
      if (!mounted) {
        return;
      }
      setState(() => _controller = controller);
      await controller.loadRequest(widget.launch.contentUri);
    } catch (error, stackTrace) {
      _failBridgeOrPage(
        context: 'Hosted WebView initialization failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleWebPermissionRequest(
    WebViewPermissionRequest request,
  ) async {
    if (!isHostedMicrophoneOnlyPermissionRequest(request.types)) {
      await request.deny();
      return;
    }
    if (!mounted || _bridgeFailed || _permissionPromptActive) {
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
    } catch (error, stackTrace) {
      try {
        await request.deny();
      } catch (_) {
        // Keep the original permission-handling failure as the primary error.
      }
      _failBridgeOrPage(
        context: 'Hosted microphone permission handling failed.',
        error: error,
        stackTrace: stackTrace,
      );
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
          '許可した場合だけ、この作品からマイクを利用できます。',
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
        // WKWebView triggers the iOS system microphone prompt after the
        // WebView permission request is granted. Info.plist is configured by
        // the TestFlight workflow.
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  Future<void> _injectBridgeForFinishedDocument(String rawUrl) async {
    if (_bridgeFailed) {
      return;
    }
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null || !_navigationPolicy.allows(uri)) {
      _failBridgeOrPage(
        context: 'Hosted WebView finished an out-of-scope navigation.',
        error: StateError('Rejected finished URL: $rawUrl'),
        stackTrace: StackTrace.current,
      );
      return;
    }
    final WebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      await controller.runJavaScript(_injector.scriptForFinishedDocument());
    } catch (error, stackTrace) {
      _failBridgeOrPage(
        context: 'Hosted bridge injection failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    if (_bridgeFailed) {
      return;
    }
    final WebViewController? controller = _controller;
    if (controller == null) {
      _failBridgeOrPage(
        context: 'Hosted bridge received a message before WebView initialization completed.',
        error: StateError('WebView controller is not ready.'),
        stackTrace: StackTrace.current,
      );
      return;
    }

    try {
      final Map<String, Object?> response =
          await _bridgeSession.handleMessage(message.message);
      final String encoded = jsonEncode(response);
      await controller.runJavaScript(
        'window.__minappBridgeReceive && window.__minappBridgeReceive($encoded);',
      );
    } catch (error, stackTrace) {
      _failBridgeOrPage(
        context: 'Hosted bridge request processing failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _failBridgeOrPage({
    required String context,
    required Object error,
    required StackTrace stackTrace,
  }) {
    _bridgeFailed = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'minapp hosted runtime bridge',
        context: ErrorDescription(context),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _error = '作品の実行を停止しました: $error');
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
