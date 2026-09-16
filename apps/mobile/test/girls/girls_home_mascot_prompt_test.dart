import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_home_mascot_prompt.dart';

void main() {
  const GirlsHomeMascotPromptResolver resolver =
      GirlsHomeMascotPromptResolver();

  test('one-person group gets invite prompt before app prompt', () {
    final GirlsHomeMascotPrompt? prompt = resolver.resolve(
      memberCount: 1,
      customAppCount: 0,
    );

    expect(prompt, isNotNull);
    expect(prompt!.message, '友達を招待する？');
    expect(
      prompt.destination,
      GirlsHomeMascotDestination.currentGroup,
    );
  });

  test('group with friends and no custom apps gets create-app prompt', () {
    final GirlsHomeMascotPrompt? prompt = resolver.resolve(
      memberCount: 2,
      customAppCount: 0,
    );

    expect(prompt, isNotNull);
    expect(prompt!.message, 'アプリを作ってみよう！');
    expect(prompt.destination, GirlsHomeMascotDestination.apps);
  });

  test('group with friends and an app has no onboarding prompt', () {
    expect(
      resolver.resolve(memberCount: 2, customAppCount: 1),
      isNull,
    );
  });

  test('invalid member count fails fast', () {
    expect(
      () => resolver.resolve(memberCount: 0, customAppCount: 0),
      throwsStateError,
    );
  });

  test('invalid custom app count fails fast', () {
    expect(
      () => resolver.resolve(memberCount: 1, customAppCount: -1),
      throwsRangeError,
    );
  });
}
