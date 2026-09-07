import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/app_mode_gate.dart';
import 'package:minapp_mobile/app_mode_store.dart';
import 'package:minapp_mobile/tenant_store.dart';

class _MemoryModeStore implements MinAppLaunchModeStore {
  MinAppLaunchMode? value;

  @override
  Future<MinAppLaunchMode?> load() async => value;

  @override
  Future<void> save(MinAppLaunchMode mode) async {
    value = mode;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _EmptyTenantStore implements TenantStore {
  @override
  Future<ConfiguredTenant?> load() async => null;

  @override
  Future<void> save(ConfiguredTenant tenant) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('fresh launch does not resolve Hosted or classroom dependencies', (
    WidgetTester tester,
  ) async {
    int hostedLoads = 0;
    int directoryLoads = 0;

    await tester.pumpWidget(
      MinAppModeGate(
        modeStore: _MemoryModeStore(),
        hostedBaseUriLoader: () async {
          hostedLoads += 1;
          throw StateError('Hosted loader must not run before selection.');
        },
        directoryLoader: () async {
          directoryLoads += 1;
          throw StateError('Directory loader must not run before selection.');
        },
        tenantStore: _EmptyTenantStore(),
        apiFactory: (_) => throw StateError('Tenant API must not be created.'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mode-hosted')), findsOneWidget);
    expect(find.byKey(const Key('mode-classroom')), findsOneWidget);
    expect(hostedLoads, 0);
    expect(directoryLoads, 0);
  });

  testWidgets('Hosted selection does not resolve classroom Directory', (
    WidgetTester tester,
  ) async {
    int hostedLoads = 0;
    int directoryLoads = 0;

    await tester.pumpWidget(
      MinAppModeGate(
        modeStore: _MemoryModeStore(),
        hostedBaseUriLoader: () async {
          hostedLoads += 1;
          throw StateError('hosted unavailable for test');
        },
        directoryLoader: () async {
          directoryLoads += 1;
          throw StateError('Directory loader must not run in Hosted mode.');
        },
        tenantStore: _EmptyTenantStore(),
        apiFactory: (_) => throw StateError('Tenant API must not be created.'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mode-hosted')));
    await tester.pumpAndSettle();

    expect(hostedLoads, 1);
    expect(directoryLoads, 0);
    expect(find.text('Hosted環境を確認できません'), findsOneWidget);
  });

  testWidgets('classroom selection does not resolve Hosted endpoint', (
    WidgetTester tester,
  ) async {
    int hostedLoads = 0;
    int directoryLoads = 0;

    await tester.pumpWidget(
      MinAppModeGate(
        modeStore: _MemoryModeStore(),
        hostedBaseUriLoader: () async {
          hostedLoads += 1;
          throw StateError('Hosted loader must not run in classroom mode.');
        },
        directoryLoader: () async {
          directoryLoads += 1;
          throw StateError('directory unavailable for test');
        },
        tenantStore: _EmptyTenantStore(),
        apiFactory: (_) => throw StateError('Tenant API must not be created.'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mode-classroom')));
    await tester.pumpAndSettle();

    expect(hostedLoads, 0);
    expect(directoryLoads, 1);
    expect(find.text('教室Directoryを確認できません'), findsOneWidget);
  });
}
