import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shopping_list/features/onboarding/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a key is unseen until marked, then seen', () async {
    final store = PrefsOnboardingStore();
    expect(await store.hasSeen(CoachKeys.stores), isFalse);

    await store.markSeen(CoachKeys.stores);
    expect(await store.hasSeen(CoachKeys.stores), isTrue);
    // Other tours are independent.
    expect(await store.hasSeen(CoachKeys.shop), isFalse);
  });

  test('resetAll clears every tour so they replay', () async {
    final store = PrefsOnboardingStore();
    for (final key in CoachKeys.all) {
      await store.markSeen(key);
    }

    await store.resetAll();

    for (final key in CoachKeys.all) {
      expect(await store.hasSeen(key), isFalse, reason: key);
    }
  });
}
