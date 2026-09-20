import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _builtInStateChannelName = 'MinAppBuiltinState';
const String _builtInStatePreferencePrefix = 'builtin_state_v1';
final RegExp _builtInAppIdPattern = RegExp(r'^[a-z0-9_-]{1,64}$');
final RegExp _builtInStateKeyPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
final RegExp _builtInStateRequestIdPattern =
    RegExp(r'^[A-Za-z0-9._-]{1,64}$');

@immutable
class BuiltInStateRequest {
  const BuiltInStateRequest({
    required this.id,
    required this.method,
    required this.key,
    this.value,
  });

  final String id;
  final String method;
  final String key;
  final Object? value;

  factory BuiltInStateRequest.decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException('Built-in state request is not valid JSON: $error');
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Built-in state request must be a JSON object.',
      );
    }

    final Map<String, Object?> payload = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry
        in decoded.entries.cast<MapEntry<Object?, Object?>>()) {
      final Object? rawKey = entry.key;
      if (rawKey is! String) {
        throw const FormatException(
          'Built-in state request keys must be strings.',
        );
      }
      payload[rawKey] = entry.value;
    }

    if (payload['version'] != 1) {
      throw const FormatException('Built-in state request version must be 1.');
    }
    final Object? rawId = payload['id'];
    final Object? rawMethod = payload['method'];
    final Object? rawKey = payload['key'];
    if (rawId is! String || !_builtInStateRequestIdPattern.hasMatch(rawId)) {
      throw const FormatException('Built-in state request id is invalid.');
    }
    if (rawMethod is! String || (rawMethod != 'get' && rawMethod != 'set')) {
      throw const FormatException('Built-in state request method is invalid.');
    }
    if (rawKey is! String || !_builtInStateKeyPattern.hasMatch(rawKey)) {
      throw const FormatException('Built-in state request key is invalid.');
    }

    final Set<String> expectedKeys = rawMethod == 'set'
        ? <String>{'version', 'id', 'method', 'key', 'value'}
        : <String>{'version', 'id', 'method', 'key'};
    final Set<String> actualKeys = payload.keys.toSet();
    if (actualKeys.length != expectedKeys.length ||
        !actualKeys.containsAll(expectedKeys)) {
      throw const FormatException('Built-in state request fields are invalid.');
    }

    return BuiltInStateRequest(
      id: rawId,
      method: rawMethod,
      key: rawKey,
      value: payload['value'],
    );
  }
}

String builtInStatePreferenceKey(String appId, String key) {
  if (!_builtInAppIdPattern.hasMatch(appId)) {
    throw ArgumentError.value(
      appId,
      'appId',
      'must be a lowercase built-in app id',
    );
  }
  if (!_builtInStateKeyPattern.hasMatch(key)) {
    throw ArgumentError.value(
      key,
      'key',
      'must be a valid built-in state key',
    );
  }
  return '$_builtInStatePreferencePrefix::$appId::$key';
}

bool isBuiltInMicrophoneOnlyPermissionRequest(
  Set<WebViewPermissionResourceType> types,
) {
  return types.length == 1 &&
      types.contains(WebViewPermissionResourceType.microphone);
}

class BuiltInWebViewPage extends StatefulWidget {
  const BuiltInWebViewPage({
    required this.appId,
    required this.title,
    required this.assetPath,
    super.key,
  });

  final String appId;
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
    _validateAppId(widget.appId);
    _validateAssetPath(widget.assetPath);
    _prepareWebView();
  }

  static void _validateAppId(String appId) {
    if (!_builtInAppIdPattern.hasMatch(appId)) {
      throw ArgumentError.value(
        appId,
        'appId',
        'Built-in app id is invalid.',
      );
    }
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
      );
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        _builtInStateChannelName,
        onMessageReceived: (JavaScriptMessage message) {
          unawaited(_handleBuiltInStateMessage(controller, message));
        },
      );
      await controller.setNavigationDelegate(
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

      // Cache is disposable. Persistent built-in state is stored through the
      // native state bridge in SharedPreferences, outside WebView cache/storage.
      await controller.clearCache();
      await controller.loadFlutterAsset(widget.assetPath);

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'ビルトインアプリを開けませんでした: $error');
    }
  }

  Future<void> _handleBuiltInStateMessage(
    WebViewController controller,
    JavaScriptMessage message,
  ) async {
    BuiltInStateRequest? request;
    try {
      request = BuiltInStateRequest.decode(message.message);
      final SharedPreferences preferences = await SharedPreferences.getInstance();
      final String preferenceKey =
          builtInStatePreferenceKey(widget.appId, request.key);

      if (request.method == 'get') {
        final String? rawValue = preferences.getString(preferenceKey);
        Object? value;
        if (rawValue != null) {
          try {
            value = jsonDecode(rawValue);
          } on FormatException catch (error) {
            throw StateError(
              'Stored built-in state is not valid JSON for ${request.key}: $error',
            );
          }
        }
        await _sendBuiltInStateResponse(
          controller,
          <String, Object?>{
            'version': 1,
            'id': request.id,
            'ok': true,
            'found': rawValue != null,
            if (rawValue != null) 'value': value,
          },
        );
        return;
      }

      final String encoded = jsonEncode(request.value);
      final bool stored = await preferences.setString(preferenceKey, encoded);
      if (!stored) {
        throw StateError(
          'SharedPreferences refused to store built-in state for ${request.key}.',
        );
      }
      await _sendBuiltInStateResponse(
        controller,
        <String, Object?>{
          'version': 1,
          'id': request.id,
          'ok': true,
        },
      );
    } catch (error) {
      final BuiltInStateRequest? failedRequest = request;
      if (failedRequest == null) {
        if (mounted) {
          setState(
            () => _error = '公式アプリの保存要求を読み取れませんでした: $error',
          );
        }
        return;
      }

      try {
        await _sendBuiltInStateResponse(
          controller,
          <String, Object?>{
            'version': 1,
            'id': failedRequest.id,
            'ok': false,
            'error': error.toString(),
          },
        );
      } catch (responseError) {
        if (mounted) {
          setState(
            () => _error =
                '公式アプリの保存処理に失敗しました: $error\n'
                'エラー応答の送信にも失敗しました: $responseError',
          );
        }
      }
    }
  }

  Future<void> _sendBuiltInStateResponse(
    WebViewController controller,
    Map<String, Object?> response,
  ) {
    final String payload = jsonEncode(response);
    return controller.runJavaScript(
      'window.__minappBuiltinStateResolve($payload);',
    );
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
