import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/hosted_app_webview.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewWidget;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const String _contentToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _otherContentToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const String _runtimeToken = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const String _origin = 'https://apps.example.com';

void main() {
  late _FakeWebViewPlatform platform;
  late _FakeRuntimeTransport transport;

  setUp(() {
    platform = _FakeWebViewPlatform();
    transport = _FakeRuntimeTransport();
    WebViewPlatform.instance = platform;
  });

  Future<void> openSession(
    WidgetTester tester,
    String path, {
    String runtimeToken = _runtimeToken,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HostedAppWebViewPage.session(
          title: 'うたってみよう',
          contentUri: Uri.parse('$_origin$path'),
          runtimeToken: runtimeToken,
          runtimeTransport: transport,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Shop session opens its content and keeps navigation scoped',
      (WidgetTester tester) async {
    const String path = '/shop/content/$_contentToken/index.html';
    await openSession(tester, path);

    expect(tester.takeException(), isNull);
    expect(find.text('うたってみよう'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('platform-webview')), findsOneWidget);
    expect(
        platform.controller!.requests.single.uri, Uri.parse('$_origin$path'));
    expect(platform.controller!.javaScriptMode, JavaScriptMode.unrestricted);

    final _FakeNavigationDelegate navigation = platform.controller!.navigation!;
    for (final String url in <String>[
      '$_origin$path',
      '$_origin/shop/content/$_contentToken/lyrics.html',
      '$_origin/shop/content/$_contentToken/index.html#verse',
    ]) {
      expect(
        await navigation.onNavigationRequest!(
          NavigationRequest(url: url, isMainFrame: true),
        ),
        NavigationDecision.navigate,
        reason: url,
      );
    }
    for (final String url in <String>[
      '$_origin/shop/content/$_otherContentToken/index.html',
      '$_origin/hosted/content/$_contentToken/index.html',
      'https://elsewhere.example.com$path',
      'http://apps.example.com$path',
      '$_origin/shop/content/$_contentToken/../other/index.html',
    ]) {
      expect(
        await navigation.onNavigationRequest!(
          NavigationRequest(url: url, isMainFrame: true),
        ),
        NavigationDecision.prevent,
        reason: url,
      );
    }
  });

  testWidgets('Shop content receives a working runtime bridge after loading',
      (WidgetTester tester) async {
    const String path = '/shop/content/$_contentToken/index.html';
    await openSession(tester, path);
    expect(tester.takeException(), isNull);

    final _FakeWebViewController controller = platform.controller!;
    controller.navigation!.onPageFinished!('$_origin$path');
    controller.navigation!.onProgress!(100);
    await tester.pumpAndSettle();

    expect(controller.scripts, hasLength(1));
    expect(controller.scripts.single, contains('minappready'));
    expect(controller.scripts.single, contains('MinAppNativeBridge'));
    expect(controller.scripts.single, isNot(contains(_runtimeToken)));
    expect(find.byType(LinearProgressIndicator), findsNothing);

    controller.channels['MinAppNativeBridge']!.onMessageReceived(
      JavaScriptMessage(
        message: jsonEncode(<String, Object?>{
          'version': 1,
          'id': 'shop-state-1',
          'method': 'state.get',
          'key': 'song',
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(transport.reads, <String>['$_runtimeToken:song']);
    expect(controller.scripts, hasLength(2));
    expect(controller.scripts.last, contains('__minappBridgeReceive'));
    expect(controller.scripts.last, contains('shop-state-1'));
    expect(controller.scripts.last, contains('sparkle'));
    expect(tester.takeException(), isNull);
  });

  for (final String route in <String>[
    'hosted/content',
    'hosted/preview',
    'hosted/authoring-preview',
  ]) {
    testWidgets('$route sessions still open and receive the runtime bridge',
        (WidgetTester tester) async {
      final String path = '/$route/$_contentToken/index.html';
      await openSession(tester, path);

      expect(tester.takeException(), isNull);
      expect(find.byType(WebViewWidget), findsOneWidget);
      final _FakeWebViewController controller = platform.controller!;
      expect(controller.requests.single.uri, Uri.parse('$_origin$path'));
      controller.navigation!.onPageFinished!('$_origin$path');
      await tester.pumpAndSettle();
      expect(controller.scripts.single, contains('minappready'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid content URL shows an error instead of an error widget',
      (WidgetTester tester) async {
    await openSession(tester, '/shop/content/invalid/index.html');

    expect(tester.takeException(), isArgumentError);
    expect(find.text('うたってみよう'), findsOneWidget);
    expect(find.textContaining(RegExp(r'作品.*(開けません|停止)')), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(platform.controller, isNull);
  });

  testWidgets('invalid runtime token shows an error before loading content',
      (WidgetTester tester) async {
    await openSession(
      tester,
      '/hosted/content/$_contentToken/index.html',
      runtimeToken: 'invalid',
    );

    expect(tester.takeException(), isArgumentError);
    expect(find.textContaining(RegExp(r'作品.*(開けません|停止)')), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(WebViewWidget), findsNothing);
    expect(platform.controller, isNull);
  });
}

class _FakeRuntimeTransport extends Fake implements HostedRuntimeTransport {
  final List<String> reads = <String>[];

  @override
  Future<Object?> getState(String runtimeToken, String key) async {
    reads.add('$runtimeToken:$key');
    return 'sparkle';
  }
}

class _FakeWebViewPlatform extends WebViewPlatform {
  _FakeWebViewController? controller;

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) =>
      _FakeCookieManager(params);

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return controller = _FakeWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _FakeWebViewWidget(params);
}

class _FakeCookieManager extends PlatformWebViewCookieManager {
  _FakeCookieManager(super.params) : super.implementation();

  @override
  Future<bool> clearCookies() async => true;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(key: ValueKey<String>('platform-webview'));
  }
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  final List<LoadRequestParams> requests = <LoadRequestParams>[];
  final List<String> scripts = <String>[];
  final Map<String, JavaScriptChannelParams> channels =
      <String, JavaScriptChannelParams>{};
  _FakeNavigationDelegate? navigation;
  JavaScriptMode? javaScriptMode;

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> clearLocalStorage() async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    javaScriptMode = mode;
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigation = handler as _FakeNavigationDelegate;
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams channel) async {
    channels[channel.name] = channel;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requests.add(params);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {
    onNavigationRequest = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    onProgress = callback;
  }
}
