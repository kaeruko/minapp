import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/builtin_state_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _ControlledPreferences extends SharedPreferencesStorePlatform {
  final Map<String, Object> data = <String, Object>{};
  final List<String> writes = <String>[];
  Completer<bool>? nextWrite;
  Object? nextWriteError;
  Object? nextReadError;
  int reads = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    reads += 1;
    final Object? error = nextReadError;
    nextReadError = null;
    if (error != null) throw error;
    return Map<String, Object>.from(data);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    final Object? error = nextWriteError;
    nextWriteError = null;
    if (error != null) throw error;
    final Completer<bool>? completion = nextWrite;
    nextWrite = null;
    if (completion != null && !await completion.future) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

String _platformKey(String appId, String key) =>
    'flutter.${builtInStatePreferenceKey(appId, key)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControlledPreferences platform;
  late SharedPreferencesStorePlatform previousPlatform;
  late BuiltInStateStore store;

  setUp(() {
    previousPlatform = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    platform = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    store = BuiltInStateStore();
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousPlatform;
  });

  test('reads existing saves and distinguishes saved null from no save',
      () async {
    platform.data[_platformKey('minappchi', 'pet')] = '{"generation":3}';
    final BuiltInStateValue oldSave = await store.get('minappchi', 'pet');
    expect(oldSave.found, isTrue);
    expect(oldSave.value, <String, Object?>{'generation': 3});

    expect((await store.get('minappchi', 'missing')).found, isFalse);
    await store.set('minappchi', 'nullable', null);
    final BuiltInStateValue savedNull =
        await BuiltInStateStore().get('minappchi', 'nullable');
    expect(savedNull.found, isTrue);
    expect(savedNull.value, isNull);
  });

  test('queued reads and writes wait for the pending save', () async {
    final Completer<bool> completion = Completer<bool>();
    platform.nextWrite = completion;
    final Future<void> first = store.set('minappchi', 'pet', 1);
    bool readCompleted = false;
    final Future<BuiltInStateValue> read = store.get('minappchi', 'pet').then(
      (BuiltInStateValue result) {
        readCompleted = true;
        return result;
      },
    );
    final Future<void> second = store.set('minappchi', 'pet', 2);

    await Future<void>.delayed(Duration.zero);
    expect(platform.writes, hasLength(1));
    expect(readCompleted, isFalse);
    expect(platform.reads, 1); // Initial preferences load only; no queued read.

    completion.complete(true);
    await first;
    expect((await read).value, 1);
    await second;
    expect((await store.get('minappchi', 'pet')).value, 2);
  });

  for (final bool throwsOnWrite in <bool>[false, true]) {
    test(
        'failed ${throwsOnWrite ? 'throwing' : 'refused'} save is not read '
        'from the preferences cache and does not stop later saves', () async {
      await store.set('minappchi', 'pet', 'saved');
      if (throwsOnWrite) {
        platform.nextWriteError = StateError('platform write failed');
      } else {
        platform.nextWrite = Completer<bool>()..complete(false);
      }

      await expectLater(
        store.set('minappchi', 'pet', 'unsaved'),
        throwsStateError,
      );
      // This reproduces the legacy plugin's cache-before-success behavior.
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      expect(
        preferences.getString(builtInStatePreferenceKey('minappchi', 'pet')),
        '"unsaved"',
      );
      expect((await store.get('minappchi', 'pet')).value, 'saved');

      await store.set('minappchi', 'pet', 'recovered');
      expect((await store.get('minappchi', 'pet')).value, 'recovered');
    });
  }

  test('queued writes snapshot values and keep app namespaces separate',
      () async {
    final Completer<bool> completion = Completer<bool>();
    platform.nextWrite = completion;
    final Future<void> blocker = store.set('minappchi', 'state', 'pet');
    final Map<String, Object?> value = <String, Object?>{
      'notes': <String>['original'],
    };
    final Future<void> queued = store.set('memo-pad', 'state', value);
    (value['notes']! as List<String>)[0] = 'changed after enqueue';

    completion.complete(true);
    await blocker;
    await queued;
    expect((await store.get('minappchi', 'state')).value, 'pet');
    expect((await store.get('memo-pad', 'state')).value, <String, Object?>{
      'notes': <String>['original'],
    });
  });

  test('reload errors and corrupt saves fail explicitly and queue recovers',
      () async {
    await store.set('minappchi', 'pet', 'saved');
    platform.nextReadError = StateError('platform read failed');
    await expectLater(store.get('minappchi', 'pet'), throwsStateError);

    platform.data[_platformKey('minappchi', 'pet')] = '{broken';
    await expectLater(store.get('minappchi', 'pet'), throwsStateError);
    expect(platform.data[_platformKey('minappchi', 'pet')], '{broken');

    platform.data[_platformKey('minappchi', 'pet')] = jsonEncode('repaired');
    expect((await store.get('minappchi', 'pet')).value, 'repaired');
  });

  test('invalid namespace and non-JSON values never enter the save queue',
      () async {
    expect(() => store.get('Invalid App', 'state'), throwsArgumentError);
    expect(() => store.set('memo-pad', 'bad key', 'text'), throwsArgumentError);
    expect(
      () => store.set('memo-pad', 'state', Object()),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(platform.writes, isEmpty);
    await store.set('memo-pad', 'state', 'valid');
    expect((await store.get('memo-pad', 'state')).value, 'valid');
  });
}
