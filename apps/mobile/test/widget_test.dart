import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/directory.dart';
import 'package:minapp_mobile/session_app.dart';
import 'package:minapp_mobile/tenant_store.dart';

class FakeApi implements MinAppApi {
  @override
  Future<AuthResult> login(String loginId, String password) async {
    expect(loginId, 'student-demo');
    expect(password, 'Password123');
    return const AuthenticatedSession(accessToken: 'token', expiresIn: 3600);
  }

  @override
  Future<AuthenticatedSession> completeNewPassword({
    required String loginId,
    required String newPassword,
    required String session,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<PublishedApp>> listPublishedApps(String accessToken) async {
    expect(accessToken, 'token');
    return <PublishedApp>[
      PublishedApp(
        appId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        versionId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        groupId: 'cccccccccccccccccccccccccccccccc',
        groupName: 'ねんね組',
        ownerLoginId: 'student-demo',
        title: 'ねんねぐみのじかんわり',
        reviewedAt: DateTime.utc(2026, 8, 17),
      ),
    ];
  }

  @override
  Future<LaunchGrant> createLaunch(String accessToken, PublishedApp app) {
    throw UnimplementedError();
  }
}

class FakeDirectory implements MinAppDirectory {
  FakeDirectory({
    required this.descriptor,
    this.resolveError,
    this.refreshError,
    this.verifyError,
  });

  final TenantDescriptor descriptor;
  final Object? resolveError;
  final Object? refreshError;
  final Object? verifyError;
  int resolveCalls = 0;
  int refreshCalls = 0;
  int verifyCalls = 0;

  @override
  Future<TenantDescriptor> resolveClassroom(String classroomCode) async {
    resolveCalls += 1;
    final Object? error = resolveError;
    if (error != null) throw error;
    expect(classroomCode, 'TZZN-PVXB-EQC3');
    return descriptor;
  }

  @override
  Future<TenantDescriptor> refreshTenant(String tenantId) async {
    refreshCalls += 1;
    expect(tenantId, descriptor.tenantId);
    final Object? error = refreshError;
    if (error != null) throw error;
    return descriptor;
  }

  @override
  Future<void> verifyTenantEndpoint(TenantDescriptor value) async {
    verifyCalls += 1;
    final Object? error = verifyError;
    if (error != null) throw error;
    expect(value.tenantId, descriptor.tenantId);
    expect(value.apiBaseUrl, descriptor.apiBaseUrl);
  }
}

class FakeTenantStore implements TenantStore {
  FakeTenantStore(this.tenant);

  ConfiguredTenant? tenant;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  Future<ConfiguredTenant?> load() async => tenant;

  @override
  Future<void> save(ConfiguredTenant value) async {
    saveCalls += 1;
    tenant = value;
  }

  @override
  Future<void> clear() async {
    clearCalls += 1;
    tenant = null;
  }
}

TenantDescriptor _descriptor() => TenantDescriptor(
      tenantId: '35cbf2c880cf41dab580d47b25ba7f0e',
      displayName: 'みんアプ 開発教室',
      apiBaseUrl: Uri.parse(
        'https://tsacejbwej.execute-api.us-west-2.amazonaws.com',
      ),
      apiProtocolVersion: 1,
      configRevision: 1,
      validForSeconds: 86400,
    );

ConfiguredTenant _configuredTenant({required bool expired}) {
  final DateTime now = DateTime.now().toUtc();
  return ConfiguredTenant(
    tenantId: '35cbf2c880cf41dab580d47b25ba7f0e',
    displayName: 'みんアプ 開発教室',
    apiBaseUrl: Uri.parse(
      'https://tsacejbwej.execute-api.us-west-2.amazonaws.com',
    ),
    apiProtocolVersion: 1,
    configRevision: 1,
    verifiedAt: expired
        ? now.subtract(const Duration(days: 2))
        : now.subtract(const Duration(hours: 1)),
    expiresAt: expired
        ? now.subtract(const Duration(days: 1))
        : now.add(const Duration(hours: 23)),
  );
}

MinApp _app({
  required FakeDirectory directory,
  required FakeTenantStore store,
  Uri? officialJoinBaseUri,
  Uri? creatorPortalBaseUri,
}) =>
    MinApp(
      directory: directory,
      tenantStore: store,
      apiFactory: (Uri baseUri) {
        expect(baseUri, _descriptor().apiBaseUrl);
        return FakeApi();
      },
      officialJoinBaseUri: officialJoinBaseUri,
      creatorPortalBaseUri: creatorPortalBaseUri,
      webViewDataClearer: () async {},
    );

void main() {
  testWidgets('cached verified tenant opens login and approved catalog', (
    WidgetTester tester,
  ) async {
    final FakeDirectory directory = FakeDirectory(descriptor: _descriptor());
    final FakeTenantStore store = FakeTenantStore(
      _configuredTenant(expired: false),
    );

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();

    expect(directory.refreshCalls, 0);
    expect(directory.verifyCalls, 0);
    expect(find.text('みんアプ'), findsOneWidget);
    expect(find.text('先生からもらったIDでログイン'), findsOneWidget);
    expect(find.text('みんアプ 開発教室'), findsNWidgets(2));
    expect(find.byKey(const Key('login-brand-header')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-id')), 'student-demo');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Password123',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('クラスの公開アプリ (1)'), findsOneWidget);
    expect(find.text('ねんねぐみのじかんわり'), findsOneWidget);
    expect(find.byKey(const Key('catalog-search')), findsOneWidget);
    expect(find.byKey(const Key('catalog-refresh')), findsOneWidget);
    expect(find.byKey(const Key('builtin-shiba-game')), findsOneWidget);
    expect(find.byKey(const Key('builtin-shiba-goshujin')), findsOneWidget);

    await tester.tap(find.text('ねんねぐみのじかんわり'));
    await tester.pumpAndSettle();

    expect(find.text('アプリの情報'), findsOneWidget);
    expect(find.text('作成者：student-demo'), findsOneWidget);
    expect(find.byKey(const Key('app-detail-launch')), findsOneWidget);
  });

  testWidgets('catalog menu shows creator portal when configured', (
    WidgetTester tester,
  ) async {
    final FakeDirectory directory = FakeDirectory(descriptor: _descriptor());
    final FakeTenantStore store = FakeTenantStore(
      _configuredTenant(expired: false),
    );

    await tester.pumpWidget(
      _app(
        directory: directory,
        store: store,
        creatorPortalBaseUri: Uri.parse('https://portal.minapp.example'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login-id')), 'student-demo');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Password123',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalog-menu')));
    await tester.pumpAndSettle();

    expect(find.text('アプリを作る・提出する'), findsOneWidget);
    expect(find.byKey(const Key('creator-portal-menu-item')), findsOneWidget);
  });

  testWidgets('first setup resolves and verifies classroom before login', (
    WidgetTester tester,
  ) async {
    final FakeDirectory directory = FakeDirectory(descriptor: _descriptor());
    final FakeTenantStore store = FakeTenantStore(null);

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();

    expect(find.text('教室を設定'), findsOneWidget);
    expect(find.text('先生からもらったIDでログイン'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('classroom-code')),
      'TZZN-PVXB-EQC3',
    );
    await tester.tap(find.byKey(const Key('classroom-submit')));
    await tester.pumpAndSettle();

    expect(directory.resolveCalls, 1);
    expect(directory.verifyCalls, 1);
    expect(store.saveCalls, 1);
    expect(store.tenant?.tenantId, _descriptor().tenantId);
    expect(find.text('先生からもらったIDでログイン'), findsOneWidget);
  });

  testWidgets('official join link is reduced to a classroom code', (
    WidgetTester tester,
  ) async {
    final FakeDirectory directory = FakeDirectory(descriptor: _descriptor());
    final FakeTenantStore store = FakeTenantStore(null);

    await tester.pumpWidget(
      _app(
        directory: directory,
        store: store,
        officialJoinBaseUri: Uri.parse('https://join.minapp.example'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('classroom-code')),
      'https://join.minapp.example/c/tzzn-pvxb-eqc3',
    );
    await tester.tap(find.byKey(const Key('classroom-submit')));
    await tester.pumpAndSettle();

    expect(directory.resolveCalls, 1);
    expect(directory.verifyCalls, 1);
    expect(store.saveCalls, 1);
    expect(find.text('先生からもらったIDでログイン'), findsOneWidget);
  });

  testWidgets('invalid classroom has an actionable error', (
    WidgetTester tester,
  ) async {
    final FakeDirectory directory = FakeDirectory(
      descriptor: _descriptor(),
      resolveError: const ApiException(
        statusCode: 404,
        code: 'classroom_not_found',
        message: 'Not found.',
      ),
    );
    final FakeTenantStore store = FakeTenantStore(null);

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('classroom-code')),
      'TZZN-PVXB-EQC3',
    );
    await tester.tap(find.byKey(const Key('classroom-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('教室コードが見つかりません。先生からもらったコードを確認してください。'),
      findsOneWidget,
    );
    expect(store.saveCalls, 0);
  });

  testWidgets('Directory failure is distinct from tenant failure', (
    WidgetTester tester,
  ) async {
    final FakeTenantStore store = FakeTenantStore(null);
    final FakeDirectory directory = FakeDirectory(
      descriptor: _descriptor(),
      resolveError: const DirectoryConnectionException('network'),
    );

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('classroom-code')),
      'TZZN-PVXB-EQC3',
    );
    await tester.tap(find.byKey(const Key('classroom-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('教室案内サービスに接続できません'), findsOneWidget);
  });

  testWidgets('tenant verification failure has a tenant-specific error', (
    WidgetTester tester,
  ) async {
    final FakeTenantStore store = FakeTenantStore(null);
    final FakeDirectory directory = FakeDirectory(
      descriptor: _descriptor(),
      verifyError: const TenantConnectionException('network'),
    );

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('classroom-code')),
      'TZZN-PVXB-EQC3',
    );
    await tester.tap(find.byKey(const Key('classroom-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('教室のサーバーを確認できません'), findsOneWidget);
    expect(store.saveCalls, 0);
  });

  testWidgets('unsupported tenant configuration asks for an app update', (
    WidgetTester tester,
  ) async {
    final FakeTenantStore store = FakeTenantStore(null);
    final FakeDirectory directory = FakeDirectory(
      descriptor: _descriptor(),
      resolveError: const AppUpdateRequiredException('unsupported protocol'),
    );

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('classroom-code')),
      'TZZN-PVXB-EQC3',
    );
    await tester.tap(find.byKey(const Key('classroom-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('この教室の環境には新しいみんアプが必要です。アプリを更新してください。'),
      findsOneWidget,
    );
  });

  testWidgets('expired tenant does not silently fall back when Directory fails', (
    WidgetTester tester,
  ) async {
    final FakeDirectory directory = FakeDirectory(
      descriptor: _descriptor(),
      refreshError: const ApiException(
        statusCode: 503,
        code: 'directory_unavailable',
        message: 'Directory unavailable.',
      ),
    );
    final FakeTenantStore store = FakeTenantStore(
      _configuredTenant(expired: true),
    );

    await tester.pumpWidget(_app(directory: directory, store: store));
    await tester.pumpAndSettle();

    expect(directory.refreshCalls, 1);
    expect(find.text('教室設定を確認できません'), findsOneWidget);
    expect(find.text('先生からもらったIDでログイン'), findsNothing);
    expect(find.byKey(const Key('tenant-retry')), findsOneWidget);
  });
}
