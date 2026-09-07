import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_authoring_contract_api.dart';
import 'package:minapp_mobile/girls/girls_authoring_resolver.dart';

void main() {
  const GirlsAuthoringAppContract editor = GirlsAuthoringAppContract(
    appId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    groupId: '11111111111111111111111111111111',
    title: 'Quiz Editor',
    edits: <String>['example/quiz@1'],
    accepts: <String>[],
  );
  const GirlsAuthoringAppContract alternateEditor = GirlsAuthoringAppContract(
    appId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    groupId: '11111111111111111111111111111111',
    title: 'Another Quiz Editor',
    edits: <String>['example/quiz@1'],
    accepts: <String>[],
  );
  const GirlsAuthoringAppContract player = GirlsAuthoringAppContract(
    appId: 'cccccccccccccccccccccccccccccccc',
    groupId: '11111111111111111111111111111111',
    title: 'Quiz Player',
    edits: <String>[],
    accepts: <String>['example/quiz@1'],
  );

  test('resolves editors and players only by content format contract', () {
    final List<GirlsAuthoringAppContract> apps =
        <GirlsAuthoringAppContract>[editor, alternateEditor, player];

    expect(
      GirlsAuthoringResolver.editorsFor(apps, 'example/quiz@1'),
      <GirlsAuthoringAppContract>[editor, alternateEditor],
    );
    expect(
      GirlsAuthoringResolver.playersFor(apps, 'example/quiz@1'),
      <GirlsAuthoringAppContract>[player],
    );
  });

  test('requireEditor validates the selected app contract', () {
    expect(
      GirlsAuthoringResolver.requireEditor(
        apps: <GirlsAuthoringAppContract>[editor, player],
        appId: editor.appId,
        contentFormat: 'example/quiz@1',
      ),
      same(editor),
    );
  });

  test('requireEditor does not silently substitute another editor', () {
    expect(
      () => GirlsAuthoringResolver.requireEditor(
        apps: <GirlsAuthoringAppContract>[alternateEditor, player],
        appId: editor.appId,
        contentFormat: 'example/quiz@1',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
