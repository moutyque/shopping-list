import 'package:shopping_list/features/onboarding/onboarding_service.dart';

/// In-memory [OnboardingStore] for widget tests. Defaults to "everything seen"
/// so coach-marks don't pop up over the widget under test.
class FakeOnboardingStore implements OnboardingStore {
  final Set<String> _seen;

  FakeOnboardingStore({bool seenAll = true})
      : _seen = seenAll ? CoachKeys.all.toSet() : <String>{};

  @override
  Future<bool> hasSeen(String key) async => _seen.contains(key);

  @override
  Future<void> markSeen(String key) async {
    _seen.add(key);
  }

  @override
  Future<void> resetAll() async => _seen.clear();
}
