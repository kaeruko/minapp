import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AppWebViewPage extends StatefulWidget {
  const AppWebViewPage({
    required this.title,
    required this.launchUrl,
    super.key,
  });

  final String title;
  final Uri launchUrl;

  @override
  State<AppWebViewPage> createState() => _AppWebViewPageState();
}

class _AppWebViewPageState extends State<AppWebViewPage> {
  WebViewController? _controller;
  String? _error;
  int _progress = 0;

  late final String _allowedPathPrefix;

  @override
  void initState() {
    super.initState();
    _allowedPathPrefix = _validateLaunchUri(widget.launchUrl);
    _prepareWebView();
  }

  Future<void> _prepareWebView() async {
    try {
      await WebViewCookieManager().clearCookies();
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
      await controller.loadRequest(widget.launchUrl);
      if (!mounted) {
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '作品を開けませんでした: $error');
    }
  }

  bool _isAllowedNavigation(Uri target) {
    return target.scheme == 'https' &&
        target.host == widget.launchUrl.host &&
        target.port == widget.launchUrl.port &&
        target.path.startsWith(_allowedPathPrefix) &&
        target.userInfo.isEmpty;
  }

  static String _validateLaunchUri(Uri uri) {
    if (uri.scheme != 'https' || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(uri, 'launchUrl', 'Launch URL must be HTTPS.');
    }
    if (uri.pathSegments.length < 3 || uri.pathSegments.first != 'launch') {
      throw ArgumentError.value(uri, 'launchUrl', 'Launch URL path is invalid.');
    }
    final String token = uri.pathSegments[1];
    final RegExp tokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
    if (!tokenPattern.hasMatch(token)) {
      throw ArgumentError.value(uri, 'launchUrl', 'Launch token is invalid.');
    }
    return '/launch/$token/';
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
