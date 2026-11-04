enum GirlsHomeMascotDestination { currentGroup, apps }

class GirlsHomeMascotPrompt {
  const GirlsHomeMascotPrompt({
    required this.message,
    required this.destination,
  });

  final String message;
  final GirlsHomeMascotDestination destination;
}

class GirlsHomeMascotPromptResolver {
  const GirlsHomeMascotPromptResolver();

  GirlsHomeMascotPrompt resolve({required int customAppCount}) {
    if (customAppCount < 0) {
      throw RangeError.value(
        customAppCount,
        'customAppCount',
        'must not be negative',
      );
    }
    if (customAppCount == 0) {
      return const GirlsHomeMascotPrompt(
        message: 'アプリを作ってみよう！',
        destination: GirlsHomeMascotDestination.apps,
      );
    }
    return const GirlsHomeMascotPrompt(
      message: 'みんなのアプリで遊ぼう！',
      destination: GirlsHomeMascotDestination.currentGroup,
    );
  }
}
