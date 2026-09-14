import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('current group id survives store instances', () async {
    const SharedPreferencesGirlsCurrentGroupStore first =
        SharedPreferencesGirlsCurrentGroupStore();
    const SharedPreferencesGirlsCurrentGroupStore second =
        SharedPreferencesGirlsCurrentGroupStore();
    const String groupId = '0123456789abcdef0123456789abcdef';

    await first.save(groupId);

    expect(await second.load(), groupId);
  });

  test('invalid stored group id fails explicitly', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      girlsCurrentGroupPreferenceKey: 'not-a-group-id',
    });
    const SharedPreferencesGirlsCurrentGroupStore store =
        SharedPreferencesGirlsCurrentGroupStore();

    expect(store.load(), throwsFormatException);
  });

  test('clear removes persisted current group', () async {
    const SharedPreferencesGirlsCurrentGroupStore store =
        SharedPreferencesGirlsCurrentGroupStore();
    const String groupId = 'fedcba9876543210fedcba9876543210';

    await store.save(groupId);
    await store.clear();

    expect(await store.load(), isNull);
  });
}
