import 'package:shared_preferences/shared_preferences.dart';

/// Identifiers for the per-screen coach-mark sequences. Each screen shows its
/// tips once, the first time it is visited.
class CoachKeys {
  static const stores = 'stores';
  static const build = 'build';
  static const shop = 'shop';

  static const all = [stores, build, shop];
}

/// Tracks which coach-mark sequences the user has already seen. Abstracted so
/// tests can substitute an in-memory implementation instead of touching disk.
abstract class OnboardingStore {
  Future<bool> hasSeen(String key);
  Future<void> markSeen(String key);

  /// Clears every seen flag so the tips play again (used by "replay").
  Future<void> resetAll();
}

/// [OnboardingStore] backed by shared_preferences.
class PrefsOnboardingStore implements OnboardingStore {
  static String _k(String key) => 'coach.$key';

  @override
  Future<bool> hasSeen(String key) async =>
      (await SharedPreferences.getInstance()).getBool(_k(key)) ?? false;

  @override
  Future<void> markSeen(String key) async =>
      (await SharedPreferences.getInstance()).setBool(_k(key), true);

  @override
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in CoachKeys.all) {
      await prefs.remove(_k(key));
    }
  }
}
