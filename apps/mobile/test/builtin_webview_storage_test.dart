import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/app_webview.dart';
import 'package:minapp_mobile/builtin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  late _StorageWebViewPlatform platform;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    platform = _StorageWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  Future<_StorageWebViewController> open(
    WidgetTester tester, {
    String appId = 'memo',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: BuiltInWebViewPage(
        appId: appId,
        title: appId,
        assetPath: 'assets/builtin/memo_pad/index.html',
      ),
    ));
    await tester.pumpAndSettle();
    return platform.controllers.last;
  }

  Future<Map<String, Object?>> request(
    WidgetTester tester,
    _StorageWebViewController controller, {
    required String method,
    String key = 'note',
    Object? value,
  }) async {
    final int before = controller.responses.length;
    controller.channels['MinAppBuiltinState']!.onMessageReceived(
      JavaScriptMessage(
          message: jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'request-$before',
        'method': method,
        'key': key,
        if (method == 'set') 'value': value,
      })),
    );
    for (int i = 0; i < 20 && controller.responses.length == before; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(controller.responses, hasLength(before + 1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((e) => e.data)
            .join('\n'));
    return controller.responses.last;
  }

  testWidgets('built-in waits for its channel without clearing browser data',
      (WidgetTester tester) async {
    platform.channelGate = Completer<void>();
    await tester.pumpWidget(const MaterialApp(
      home: BuiltInWebViewPage(
        appId: 'memo',
        title: 'Memo',
        assetPath: 'assets/builtin/memo_pad/index.html',
      ),
    ));
    await tester.pump();
    final _StorageWebViewController controller = platform.controllers.single;
    expect(controller.assets, isEmpty);
    platform.channelGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.assets, <String>['assets/builtin/memo_pad/index.html']);
    expect(controller.channels, contains('MinAppBuiltinState'));
    expect(platform.cacheClears, 0);
    expect(platform.localStorageClears, 0);
    expect(platform.cookieClears, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save survives browser cleanup and a new WebView, scoped by app',
      (WidgetTester tester) async {
    final _StorageWebViewController first = await open(tester);
    expect((await request(tester, first, method: 'get'))['found'], false);
    expect(
      (await request(tester, first, method: 'set', value: '大切なメモ'))['ok'],
      true,
    );
    await tester.pumpWidget(const SizedBox());
    await clearMinAppWebViewData();
    expect(platform.cacheClears, 1);
    expect(platform.localStorageClears, 1);
    expect(platform.cookieClears, 1);

    final _StorageWebViewController reopened = await open(tester);
    final Map<String, Object?> restored =
        await request(tester, reopened, method: 'get');
    expect(restored['found'], true);
    expect(restored['value'], '大切なメモ');
    await tester.pumpWidget(const SizedBox());

    final _StorageWebViewController other =
        await open(tester, appId: 'minappchi');
    expect((await request(tester, other, method: 'get'))['found'], false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt saves return an error and keep the stored data',
      (WidgetTester tester) async {
    final String key = builtInStatePreferenceKey('memo', 'note');
    SharedPreferences.setMockInitialValues(<String, Object>{key: '{broken'});
    final _StorageWebViewController controller = await open(tester);
    final Map<String, Object?> response =
        await request(tester, controller, method: 'get');
    expect(response['ok'], false);
    expect(response['error'], contains('not valid JSON'));
    expect(response.containsKey('found'), false);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(key), '{broken');
  });

  testWidgets('stored JSON null is distinguishable from a missing save',
      (WidgetTester tester) async {
    final _StorageWebViewController controller = await open(tester);
    expect((await request(tester, controller, method: 'set'))['ok'], true);
    final Map<String, Object?> response =
        await request(tester, controller, method: 'get');
    expect(response['found'], true);
    expect(response.containsKey('value'), true);
    expect(response['value'], isNull);
  });
}

class _StorageWebViewPlatform extends WebViewPlatform {
  final List<_StorageWebViewController> controllers =
      <_StorageWebViewController>[];
  Completer<void>? channelGate;
  int cookieClears = 0;
  int cacheClears = 0;
  int localStorageClears = 0;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final _StorageWebViewController controller =
        _StorageWebViewController(params, this);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) =>
      _StorageCookieManager(params, this);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _StorageNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _StorageWebViewWidget(params);
}

class _StorageWebViewController extends PlatformWebViewController {
  _StorageWebViewController(super.params, this.platform)
      : super.implementation();

  final _StorageWebViewPlatform platform;
  final Map<String, JavaScriptChannelParams> channels =
      <String, JavaScriptChannelParams>{};
  final List<String> assets = <String>[];
  final List<Map<String, Object?>> responses = <Map<String, Object?>>[];

  @override
  Future<void> clearCache() async => platform.cacheClears++;

  @override
  Future<void> clearLocalStorage() async => platform.localStorageClears++;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) callback,
  ) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams channel) async {
    if (platform.channelGate != null) await platform.channelGate!.future;
    channels[channel.name] = channel;
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    expectSync(channels, contains('MinAppBuiltinState'));
    assets.add(key);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    const String prefix = 'window.__minappBuiltinStateResolve(';
    expectSync(javaScript, startsWith(prefix));
    responses.add(Map<String, Object?>.from(
      jsonDecode(javaScript.substring(prefix.length, javaScript.length - 2))
          as Map,
    ));
  }
}

class _StorageCookieManager extends PlatformWebViewCookieManager {
  _StorageCookieManager(super.params, this.platform) : super.implementation();
  final _StorageWebViewPlatform platform;

  @override
  Future<bool> clearCookies() async {
    platform.cookieClears++;
    return true;
  }
}

class _StorageNavigationDelegate extends PlatformNavigationDelegate {
  _StorageNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
}

class _StorageWebViewWidget extends PlatformWebViewWidget {
  _StorageWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();
}
