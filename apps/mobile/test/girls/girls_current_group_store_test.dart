import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String userA = '11111111111111111111111111111111';
  const String userB = '22222222222222222222222222222222';
  const String groupA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const String groupB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('remembers a different current group for each account', () async {
    const SharedPreferencesGirlsCurrentGroupStore first =
        SharedPreferencesGirlsCurrentGroupStore();
    const SharedPreferencesGirlsCurrentGroupStore second =
        SharedPreferencesGirlsCurrentGroupStore();

    await first.activateAccount(userA);
    await first.save(groupA);
    await first.deactivateAccount();

    await second.activateAccount(userB);
    await second.save(groupB);
    expect(await second.load(), groupB);

    await second.activateAccount(userA);
    expect(await first.load(), groupA);

    await first.activateAccount(userB);
    expect(await second.load(), groupB);
  });

  test('deactivation preserves remembered group but removes active scope',
      () async {
    const SharedPreferencesGirlsCurrentGroupStore store =
        SharedPreferencesGirlsCurrentGroupStore();

    await store.activateAccount(userA);
    await store.save(groupA);
    await store.deactivateAccount();

    await expectLater(store.load(), throwsStateError);

    await store.activateAccount(userA);
    expect(await store.load(), groupA);
  });

  test('invalid stored group id fails explicitly for active account', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      girlsCurrentGroupAccountPreferenceKey: userA,
      '$girlsCurrentGroupPreferencePrefix$userA': 'not-a-group-id',
    });
    const SharedPreferencesGirlsCurrentGroupStore store =
        SharedPreferencesGirlsCurrentGroupStore();

    expect(store.load(), throwsFormatException);
  });

  test('clear removes only the active accounts remembered group', () async {
    const SharedPreferencesGirlsCurrentGroupStore store =
        SharedPreferencesGirlsCurrentGroupStore();

    await store.activateAccount(userA);
    await store.save(groupA);
    await store.activateAccount(userB);
    await store.save(groupB);

    await store.clear();
    expect(await store.load(), isNull);

    await store.activateAccount(userA);
    expect(await store.load(), groupA);
  });

  test('load fails explicitly before an account is activated', () async {
    const SharedPreferencesGirlsCurrentGroupStore store =
        SharedPreferencesGirlsCurrentGroupStore();

    await expectLater(store.load(), throwsStateError);
  });
}
