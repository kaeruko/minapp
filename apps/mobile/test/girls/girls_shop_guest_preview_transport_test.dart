import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_shop_guest_preview_transport.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';

void main() {
  test('anonymous preview state is isolated and discarded on close', () async {
    final GirlsGuestPreviewRuntimeTransport one = GirlsGuestPreviewRuntimeTransport();
    final GirlsGuestPreviewRuntimeTransport two = GirlsGuestPreviewRuntimeTransport();
    expect(one.runtimeToken, isNot(two.runtimeToken));
    expect(one.runtimeToken.length, inInclusiveRange(32, 64));
    await one.setState(one.runtimeToken, 'score', <String, Object?>{'points': 5});
    await one.setUserState(one.runtimeToken, 'score', 99);
    expect(
      await one.getState(one.runtimeToken, 'score'),
      <String, Object?>{'points': 5},
    );
    expect(await one.getUserState(one.runtimeToken, 'score'), 99);
    await expectLater(
      two.getState(two.runtimeToken, 'score'),
      throwsA(isA<ApiException>().having((ApiException e) => e.statusCode, 'status', 404)),
    );
    await expectLater(one.getState(two.runtimeToken, 'score'), throwsArgumentError);
    await one.deleteState(one.runtimeToken, 'score');
    await expectLater(
      one.getState(one.runtimeToken, 'score'),
      throwsA(isA<ApiException>().having((ApiException e) => e.statusCode, 'status', 404)),
    );
    one.close();
    await expectLater(one.getUserState(one.runtimeToken, 'score'), throwsStateError);
    await expectLater(two.getState(two.runtimeToken, 'score'), throwsA(isA<ApiException>()));
    two.close();
  });

  test('preview storage snapshots mutable JSON values', () async {
    final GirlsGuestPreviewRuntimeTransport store = GirlsGuestPreviewRuntimeTransport();
    final List<int> input = <int>[1, 2];
    await store.setState(store.runtimeToken, 'values', input);
    input.add(3);
    final List<Object?> returned =
        (await store.getState(store.runtimeToken, 'values'))! as List<Object?>;
    expect(returned, <int>[1, 2]);
    returned.add(4);
    expect(await store.getState(store.runtimeToken, 'values'), <int>[1, 2]);
    store.close();
  });

  test('guest storage enforces existing runtime value limit', () async {
    final GirlsGuestPreviewRuntimeTransport store = GirlsGuestPreviewRuntimeTransport();
    await expectLater(
      store.setState(store.runtimeToken, 'large', List<String>.filled(16 * 1024, 'x').join()),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.code,
          'code',
          'runtime_value_too_large',
        ),
      ),
    );
    store.close();
  });

  test('each preview uses the normal Hosted bridge protocol', () async {
    final GirlsGuestPreviewRuntimeTransport store = GirlsGuestPreviewRuntimeTransport();
    final HostedBridgeSession bridge = HostedBridgeSession(
      transport: store,
      runtimeToken: store.runtimeToken,
    );
    final Map<String, Object?> set = await bridge.handleMessage(
      '{"version":1,"id":"set1","method":"state.set","key":"score","value":7}',
    );
    expect(set['id'], 'set1');
    final Map<String, Object?> get = await bridge.handleMessage(
      '{"version":1,"id":"get1","method":"state.get","key":"score"}',
    );
    expect(get.toString(), contains('7'));
    store.close();
  });
}
