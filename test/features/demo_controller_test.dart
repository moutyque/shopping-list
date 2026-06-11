import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/data/db/app_database.dart';
import 'package:shopping_list/data/repositories/drift_repositories.dart';
import 'package:shopping_list/features/onboarding/demo_controller.dart';
import 'package:shopping_list/features/onboarding/demo_data.dart';

class _RecordingNav implements DemoNavigator {
  final calls = <String>[];
  @override
  void openBuildList(Store store, ShoppingList list) => calls.add('build');
  @override
  void openZones(Store store) => calls.add('zones');
  @override
  void openShopping(Store store, ShoppingList list) => calls.add('shop');
  @override
  void backToStores() => calls.add('back');
}

const _strings = DemoStrings(
  storeName: 'Demo Market',
  zones: ['Produce', 'Bakery', 'Dairy', 'Frozen'],
  items: [
    ('Bananas', 'Produce'),
    ('Milk', 'Dairy'),
    ('Bread', 'Bakery'),
  ],
);

const _narration = DemoNarration(
  creating: ('c', 'cb'),
  adding: ('a', 'ab'),
  reordering: ('r', 'rb'),
  shopping: ('s', 'sb'),
  done: ('d', 'db'),
);

void main() {
  late AppDatabase db;
  late DriftStoreRepository stores;

  DemoController build(_RecordingNav nav, List<DemoStep> steps) {
    final zones = DriftZoneRepository(db);
    final catalog = DriftCatalogRepository(db);
    final lists = DriftListRepository(db);
    return DemoController(
      stores: stores,
      zones: zones,
      catalog: catalog,
      lists: lists,
      nav: nav,
      strings: _strings,
      narration: _narration,
      onStep: steps.add,
      pace: Duration.zero,
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    stores = DriftStoreRepository(db);
  });
  tearDown(() async => db.close());

  test('runs the full flow then cleans up the demo store', () async {
    final nav = _RecordingNav();
    final steps = <DemoStep>[];

    await build(nav, steps).run();

    // Visited each screen in order and returned home.
    expect(nav.calls, ['build', 'zones', 'shop', 'back']);
    // Narrated every stage with title + body.
    expect(steps.map((s) => s.title), ['c', 'a', 'r', 's', 'd']);
    expect(steps.map((s) => s.body), ['cb', 'ab', 'rb', 'sb', 'db']);
    // The action stages spotlight the content area; setup/done dim fully.
    expect(steps.map((s) => s.focus), [
      DemoFocus.none,
      DemoFocus.body,
      DemoFocus.body,
      DemoFocus.body,
      DemoFocus.none,
    ]);
    // The demo store was deleted at the end — clean slate.
    expect(await stores.mostUsedStore(), isNull);
  });

  test('aborting stops early and still deletes the demo store', () async {
    final nav = _RecordingNav();
    final controller = build(nav, <DemoStep>[]);
    controller.abort();

    await controller.run();

    expect(await stores.mostUsedStore(), isNull);
    expect(nav.calls.last, 'back');
  });
}
