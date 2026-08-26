import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/ugc_safety.dart';

void main() {
  const String creatorId = 'dddddddddddddddddddddddddddddddd';

  test('memory creator safety store hides and restores by stable user id', () async {
    final MemoryCreatorSafetyStore store = MemoryCreatorSafetyStore();

    expect(await store.loadHiddenCreatorUserIds(), isEmpty);

    await store.hideCreator(creatorId);
    expect(await store.loadHiddenCreatorUserIds(), <String>{creatorId});

    await store.hideCreator(creatorId);
    expect(await store.loadHiddenCreatorUserIds(), <String>{creatorId});

    await store.unhideCreator(creatorId);
    expect(await store.loadHiddenCreatorUserIds(), isEmpty);
  });

  test('creator safety store rejects unstable or malformed ids', () async {
    final MemoryCreatorSafetyStore store = MemoryCreatorSafetyStore();

    await expectLater(
      store.hideCreator('student-demo'),
      throwsArgumentError,
    );
    await expectLater(
      store.hideCreator('D' * 32),
      throwsArgumentError,
    );
  });
}
