import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shopping_list/features/onboarding/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the demo flag is unseen until marked, then seen', () async {
    final store = PrefsOnboardingStore();
    expect(await store.hasSeen(DemoFlag.seen), isFalse);

    await store.markSeen(DemoFlag.seen);
    expect(await store.hasSeen(DemoFlag.seen), isTrue);
  });

  test('resetAll clears the flag so the demo replays', () async {
    final store = PrefsOnboardingStore();
    await store.markSeen(DemoFlag.seen);

    await store.resetAll();

    expect(await store.hasSeen(DemoFlag.seen), isFalse);
  });
}
