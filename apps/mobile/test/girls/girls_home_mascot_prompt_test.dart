import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_home_mascot_prompt.dart';

void main() {
  const GirlsHomeMascotPromptResolver resolver =
      GirlsHomeMascotPromptResolver();

  test('empty community gets create-app prompt', () {
    final GirlsHomeMascotPrompt prompt = resolver.resolve(customAppCount: 0);

    expect(prompt.message, 'アプリを作ってみよう！');
    expect(prompt.destination, GirlsHomeMascotDestination.apps);
  });

  test('community with an app gets play prompt', () {
    final GirlsHomeMascotPrompt prompt = resolver.resolve(customAppCount: 1);

    expect(prompt.message, 'みんなのアプリで遊ぼう！');
    expect(prompt.destination, GirlsHomeMascotDestination.currentGroup);
  });

  test('invalid custom app count fails fast', () {
    expect(() => resolver.resolve(customAppCount: -1), throwsRangeError);
  });
}
