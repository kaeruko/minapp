import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'hosted_authoring_bridge.dart';
import 'hosted_authoring_launch_client.dart';
import 'hosted_authoring_preview_bridge.dart';
import 'hosted_runtime_bridge.dart';

final RegExp _previewTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
final RegExp _authoringEditorTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');

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
  })  : sessionContentUri = null,
        sessionRuntimeToken = null,
        authoringLaunch = null,
        authoringTransport = null,
        authoringPreviewHost = null;

  const HostedAppWebViewPage.session({
    required this.title,
    required Uri contentUri,
    required String runtimeToken,
    required this.runtimeTransport,
    super.key,
  })  : launch = null,
        sessionContentUri = contentUri,
        sessionRuntimeToken = runtimeToken,
        authoringLaunch = null,
        authoringTransport = null,
        authoringPreviewHost = null;

  HostedAppWebViewPage.authoring({
    required this.title,
    required HostedAuthoringLaunchGrant launch,
    required this.runtimeTransport,
    required HostedAuthoringTransport authoringTransport,
    required HostedAuthoringPreviewHost authoringPreviewHost,
    super.key,
  })  : launch = null,
        sessionContentUri = launch.contentUri,
        sessionRuntimeToken = launch.runtimeToken,
        authoringLaunch = launch,
        authoringTransport = authoringTransport,
        authoringPreviewHost = authoringPreviewHost;

  final String title;
  final HostedLaunchGrant? launch;
  final Uri? sessionContentUri;
  final String? sessionRuntimeToken;
  final HostedRuntimeTransport runtimeTransport;
  final HostedAuthoringLaunchGrant? authoringLaunch;
  final HostedAuthoringTransport? authoringTransport;
  final HostedAuthoringPreviewHost? authoringPreviewHost;

  Uri get contentUri {
    final HostedLaunchGrant? launchGrant = launch;
    if (launchGrant != null) return launchGrant.contentUri;
    final Uri? value = sessionContentUri;
    if (value == null) {
      throw StateError('Hosted WebView session has no content URI.');
    }
    return value;
  }

  String get runtimeToken {
    final HostedLaunchGrant? launchGrant = launch;
    if (launchGrant != null) return launchGrant.runtimeToken;
    final String? value = sessionRuntimeToken;
    if (value == null || value.isEmpty) {
      throw StateError('Hosted WebView session has no Runtime token.');
    }
    return value;
  }

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

  late final bool Function(Uri target) _allowsNavigation;
  late final HostedBridgeSession _bridgeSession;
  late final HostedAuthoringBridgeSession? _authoringBridgeSession;
  late final HostedAuthoringPreviewBridgeSession? _authoringPreviewBridgeSession;
  final HostedBridgeDocumentInjector _injector = HostedBridgeDocumentInjector();
  final HostedAuthoringBridgeDocumentInjector _authoringInjector =
      HostedAuthoringBridgeDocumentInjector();
  final HostedAuthoringPreviewBridgeDocumentInjector _authoringPreviewInjector =
      HostedAuthoringPreviewBridgeDocumentInjector();

  @override
  void initState() {
    super.initState();
    final Uri contentUri = widget.contentUri;
    if (widget.authoringLaunch != null) {
      final _HostedAuthoringEditorNavigationPolicy policy =
          _HostedAuthoringEditorNavigationPolicy(contentUri);
      _allowsNavigation = policy.allows;
    } else if (_HostedPreviewNavigationPolicy.isPreviewUri(contentUri)) {
      final _HostedPreviewNavigationPolicy policy =
          _HostedPreviewNavigationPolicy(contentUri);
      _allowsNavigation = policy.allows;
    } else {
      final HostedContentNavigationPolicy policy =
          HostedContentNavigationPolicy(contentUri);
      _allowsNavigation = policy.allows;
    }
    _bridgeSession = HostedBridgeSession(
      transport: widget.runtimeTransport,
      runtimeToken: widget.runtimeToken,
    );
    final HostedAuthoringLaunchGrant? authoringLaunch = widget.authoringLaunch;
    if (authoringLaunch == null) {
      _authoringBridgeSession = null;
      _authoringPreviewBridgeSession = null;
    } else {
      final HostedAuthoringTransport? authoringTransport = widget.authoringTransport;
      if (authoringTransport == null) {
        throw StateError('Authoring WebView has no Authoring transport.');
      }
      final HostedAuthoringPreviewHost? authoringPreviewHost =
          widget.authoringPreviewHost;
      if (authoringPreviewHost == null) {
        throw StateError('Authoring WebView has no Preview host action.');
      }
      _authoringBridgeSession = HostedAuthoringBridgeSession(
        transport: authoringTransport,
        authoringToken: authoringLaunch.authoringToken,
      );
      _authoringPreviewBridgeSession = HostedAuthoringPreviewBridgeSession(
        preview: authoringPreviewHost,
      );
    }
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
              if (target == null || !_allowsNavigation(target)) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageFinished: (String url) {
              _injectBridgeForFinishedDocument(url);
            },
          ),
        );
      if (_authoringBridgeSession != null) {
        await controller.addJavaScriptChannel(
          'MinAppAuthoringBridge',
          onMessageReceived: _onAuthoringBridgeMessage,
        );
      }
      if (_authoringPreviewBridgeSession != null) {
        await controller.addJavaScriptChannel(
          'MinAppAuthoringPreviewBridge',
          onMessageReceived: _onAuthoringPreviewBridgeMessage,
        );
      }
      await controller.clearLocalStorage();
      await controller.clearCache();
      if (!mounted) {
        return;
      }
      setState(() => _controller = controller);
      await controller.loadRequest(widget.contentUri);
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
    if (uri == null || !_allowsNavigation(uri)) {
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
      if (_authoringBridgeSession != null) {
        await controller.runJavaScript(
          _authoringInjector.scriptForFinishedDocument(),
        );
      }
      if (_authoringPreviewBridgeSession != null) {
        await controller.runJavaScript(
          _authoringPreviewInjector.scriptForFinishedDocument(),
        );
      }
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

  Future<void> _onAuthoringBridgeMessage(JavaScriptMessage message) async {
    if (_bridgeFailed) {
      return;
    }
    final HostedAuthoringBridgeSession? authoringBridgeSession =
        _authoringBridgeSession;
    if (authoringBridgeSession == null) {
      _failBridgeOrPage(
        context: 'Authoring bridge received a message outside Authoring mode.',
        error: StateError('Authoring bridge is not enabled for this WebView.'),
        stackTrace: StackTrace.current,
      );
      return;
    }
    final WebViewController? controller = _controller;
    if (controller == null) {
      _failBridgeOrPage(
        context: 'Authoring bridge received a message before WebView initialization completed.',
        error: StateError('WebView controller is not ready.'),
        stackTrace: StackTrace.current,
      );
      return;
    }

    try {
      final Map<String, Object?> response =
          await authoringBridgeSession.handleMessage(message.message);
      final String encoded = jsonEncode(response);
      await controller.runJavaScript(
        'window.__minappAuthoringBridgeReceive && '
        'window.__minappAuthoringBridgeReceive($encoded);',
      );
    } catch (error, stackTrace) {
      _failBridgeOrPage(
        context: 'Authoring bridge request processing failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _onAuthoringPreviewBridgeMessage(JavaScriptMessage message) async {
    if (_bridgeFailed) {
      return;
    }
    final HostedAuthoringPreviewBridgeSession? previewBridgeSession =
        _authoringPreviewBridgeSession;
    if (previewBridgeSession == null) {
      _failBridgeOrPage(
        context: 'Authoring Preview bridge received a message outside Authoring mode.',
        error: StateError('Authoring Preview bridge is not enabled for this WebView.'),
        stackTrace: StackTrace.current,
      );
      return;
    }
    final WebViewController? controller = _controller;
    if (controller == null) {
      _failBridgeOrPage(
        context: 'Authoring Preview bridge received a message before WebView initialization completed.',
        error: StateError('WebView controller is not ready.'),
        stackTrace: StackTrace.current,
      );
      return;
    }

    try {
      final Map<String, Object?> response =
          await previewBridgeSession.handleMessage(message.message);
      final String encoded = jsonEncode(response);
      await controller.runJavaScript(
        'window.__minappAuthoringPreviewBridgeReceive && '
        'window.__minappAuthoringPreviewBridgeReceive($encoded);',
      );
    } catch (error, stackTrace) {
      _failBridgeOrPage(
        context: 'Authoring Preview bridge request processing failed.',
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

class _HostedPreviewNavigationPolicy {
  _HostedPreviewNavigationPolicy(Uri contentUri)
      : _contentUri = _validateContentUri(contentUri),
        _allowedPathPrefix = _contentPathPrefix(contentUri);

  final Uri _contentUri;
  final String _allowedPathPrefix;

  static bool isPreviewUri(Uri uri) {
    final List<String> segments = uri.pathSegments;
    return segments.length == 4 &&
        segments[0] == 'hosted' &&
        segments[1] == 'preview';
  }

  bool allows(Uri target) {
    return target.scheme == 'https' &&
        target.host == _contentUri.host &&
        target.port == _contentUri.port &&
        target.userInfo.isEmpty &&
        !_containsTraversalSegment(target) &&
        target.path.startsWith(_allowedPathPrefix);
  }

  static Uri _validateContentUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        _containsTraversalSegment(uri)) {
      throw ArgumentError.value(
        uri,
        'contentUri',
        'Hosted preview URL is invalid.',
      );
    }
    final List<String> segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'hosted' ||
        segments[1] != 'preview' ||
        !_previewTokenPattern.hasMatch(segments[2]) ||
        segments[3] != 'index.html') {
      throw ArgumentError.value(
        uri,
        'contentUri',
        'Hosted preview URL path is invalid.',
      );
    }
    return uri;
  }

  static String _contentPathPrefix(Uri uri) {
    final List<String> segments = uri.pathSegments;
    return '/hosted/preview/${segments[2]}/';
  }

  static bool _containsTraversalSegment(Uri uri) {
    return uri.pathSegments.any(
      (String segment) => segment == '.' || segment == '..',
    );
  }
}

class _HostedAuthoringEditorNavigationPolicy {
  _HostedAuthoringEditorNavigationPolicy(Uri contentUri)
      : _contentUri = _validateContentUri(contentUri),
        _allowedPathPrefix = _contentPathPrefix(contentUri);

  final Uri _contentUri;
  final String _allowedPathPrefix;

  bool allows(Uri target) {
    return target.scheme == 'https' &&
        target.host == _contentUri.host &&
        target.port == _contentUri.port &&
        target.userInfo.isEmpty &&
        !_containsTraversalSegment(target) &&
        target.path.startsWith(_allowedPathPrefix);
  }

  static Uri _validateContentUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        _containsTraversalSegment(uri)) {
      throw ArgumentError.value(
        uri,
        'contentUri',
        'Hosted Authoring Editor URL is invalid.',
      );
    }
    final List<String> segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'hosted' ||
        segments[1] != 'authoring-editor' ||
        !_authoringEditorTokenPattern.hasMatch(segments[2]) ||
        segments[3] != 'index.html') {
      throw ArgumentError.value(
        uri,
        'contentUri',
        'Hosted Authoring Editor URL path is invalid.',
      );
    }
    return uri;
  }

  static String _contentPathPrefix(Uri uri) {
    final List<String> segments = uri.pathSegments;
    return '/hosted/authoring-editor/${segments[2]}/';
  }

  static bool _containsTraversalSegment(Uri uri) {
    return uri.pathSegments.any(
      (String segment) => segment == '.' || segment == '..',
    );
  }
}
