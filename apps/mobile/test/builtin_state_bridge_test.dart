import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/builtin_webview.dart';

void main() {
  test('built-in state request decodes strict get and set messages', () {
    final BuiltInStateRequest getRequest = BuiltInStateRequest.decode(
      '{"version":1,"id":"minappchi-1","method":"get","key":"minappchi_pet_v1"}',
    );
    expect(getRequest.id, 'minappchi-1');
    expect(getRequest.method, 'get');
    expect(getRequest.key, 'minappchi_pet_v1');
    expect(getRequest.value, isNull);

    final BuiltInStateRequest setRequest = BuiltInStateRequest.decode(
      '{"version":1,"id":"minappchi-2","method":"set","key":"minappchi_pet_v1","value":{"generation":3}}',
    );
    expect(setRequest.method, 'set');
    expect(setRequest.value, <String, Object?>{'generation': 3});
  });

  test('built-in state request rejects protocol drift', () {
    expect(
      () => BuiltInStateRequest.decode(
        '{"version":1,"id":"x","method":"get","key":"state","extra":true}',
      ),
      throwsFormatException,
    );
    expect(
      () => BuiltInStateRequest.decode(
        '{"version":1,"id":"x","method":"delete","key":"state"}',
      ),
      throwsFormatException,
    );
  });

  test('built-in state preference key is namespaced by app id', () {
    expect(
      builtInStatePreferenceKey('minappchi', 'minappchi_pet_v1'),
      'builtin_state_v1::minappchi::minappchi_pet_v1',
    );
    expect(
      () => builtInStatePreferenceKey('MinAppchi', 'state'),
      throwsArgumentError,
    );
  });
}
