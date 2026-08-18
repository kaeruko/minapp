import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  WebViewController? _controller;
  String? _error;
  int _progress = 0;

  static final RegExp _assetPathPattern = RegExp(
    r'^assets/builtin/[a-z0-9_-]+/index\.html$',
  );

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

  Future<void> _prepareWebView() async {
    try {
      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() => _progress = progress);
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

      await controller.clearLocalStorage();
      await controller.clearCache();
      await controller.loadFlutterAsset(widget.assetPath);

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'ビルトインアプリを開けませんでした: $error');
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
