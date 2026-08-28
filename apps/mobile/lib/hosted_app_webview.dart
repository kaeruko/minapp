import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'hosted_runtime_bridge.dart';

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
  WebViewController? _controller;
  String? _error;
  int _progress = 0;
  bool _bridgeFailed = false;

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
      final WebViewController controller = WebViewController()
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
