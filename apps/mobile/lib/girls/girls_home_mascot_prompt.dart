enum GirlsHomeMascotDestination { invite, currentGroup, apps }

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

  GirlsHomeMascotPrompt? resolve({
    required int memberCount,
    required int customAppCount,
  }) {
    if (memberCount < 1) {
      throw StateError('Current group must contain at least one member.');
    }
    if (customAppCount < 0) {
      throw RangeError.value(
        customAppCount,
        'customAppCount',
        'must not be negative',
      );
    }

    // The social onboarding hint takes precedence when both conditions match.
    if (memberCount == 1) {
      return const GirlsHomeMascotPrompt(
        message: '友達を招待する？',
        destination: GirlsHomeMascotDestination.invite,
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
