import 'package:shared_preferences/shared_preferences.dart';

/// Persisted flag keys for onboarding.
class DemoFlag {
  /// Whether the autonomous demo has already played on first launch.
  static const seen = 'demo_seen';

  static const all = [seen];
}

/// Tracks which onboarding has already been shown. Abstracted so tests can
/// substitute an in-memory implementation instead of touching disk.
abstract class OnboardingStore {
  Future<bool> hasSeen(String key);
  Future<void> markSeen(String key);

  /// Clears every flag so the demo plays again (used by "replay").
  Future<void> resetAll();
}

/// [OnboardingStore] backed by shared_preferences.
class PrefsOnboardingStore implements OnboardingStore {
  static String _k(String key) => 'onboarding.$key';

  @override
  Future<bool> hasSeen(String key) async =>
      (await SharedPreferences.getInstance()).getBool(_k(key)) ?? false;

  @override
  Future<void> markSeen(String key) async =>
      (await SharedPreferences.getInstance()).setBool(_k(key), true);

  @override
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in DemoFlag.all) {
      await prefs.remove(_k(key));
    }
  }
}
