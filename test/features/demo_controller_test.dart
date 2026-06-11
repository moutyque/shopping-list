import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/core/learning/learning_models.dart';
import 'package:shopping_list/core/learning/learning_service.dart';
import 'package:shopping_list/data/db/app_database.dart';
import 'package:shopping_list/data/repositories/drift_repositories.dart';
import 'package:shopping_list/features/onboarding/demo_conductor.dart';
import 'package:shopping_list/features/onboarding/demo_controller.dart';
import 'package:shopping_list/features/onboarding/demo_data.dart';

class _RecordingNav implements DemoNavigator {
  final calls = <String>[];
  @override
  void openZones(Store store) => calls.add('zones');
  @override
  void openBuildList(Store store, ShoppingList list) => calls.add('build');
  @override
  void openShopping(Store store, ShoppingList list) => calls.add('shop');
  @override
  void backToStores() => calls.add('back');
}

/// Items in walk order: Produce, Bakery, Dairy, Dairy. The controller adds them
/// reversed (jumbled) but checks them off in this order, so the learned route
/// should sort a later list back into this sequence.
const _strings = DemoStrings(
  storeName: 'Demo Market',
  zones: ['Produce', 'Bakery', 'Dairy'],
  items: [
    ('Bananas', 'Produce'),
    ('Bread', 'Bakery'),
    ('Milk', 'Dairy'),
    ('Eggs', 'Dairy'),
  ],
);

DemoNarration _narration() {
  // Distinct titles so the step order can be asserted; bodies unused here.
  (String, String) c(String t) => (t, '$t.body');
  return DemoNarration(
    intro: c('intro'),
    addAisle: c('addAisle'),
    nameAisle: c('nameAisle'),
    confirmAisle: c('confirmAisle'),
    restAisles: c('restAisles'),
    typeItem: c('typeItem'),
    tapAdd: c('tapAdd'),
    restItems: c('restItems'),
    check: c('check'),
    complete: c('complete'),
    reveal: c('reveal'),
    done: c('done'),
  );
}

void main() {
  late AppDatabase db;
  late DriftStoreRepository stores;

  DemoController build(
    _RecordingNav nav,
    DemoConductor conductor,
    List<DemoStep> steps,
  ) {
    return DemoController(
      stores: stores,
      zones: DriftZoneRepository(db),
      catalog: DriftCatalogRepository(db),
      lists: DriftListRepository(db),
      nav: nav,
      conductor: conductor,
      strings: _strings,
      narration: _narration(),
      onStep: steps.add,
      settle: Duration.zero,
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    stores = DriftStoreRepository(db);
  });
  tearDown(() async => db.close());

  test('walks every step in order then cleans up the demo store', () async {
    final nav = _RecordingNav();
    final conductor = DemoConductor(autoAdvance: true);
    final steps = <DemoStep>[];

    await build(nav, conductor, steps).run();

    // Trip 1: zones -> build -> shop. Reset to stores, then trip 2 opens a
    // fresh shopping screen for the reveal. Finally return home.
    expect(nav.calls, ['zones', 'build', 'shop', 'back', 'shop', 'back']);
    // Every beat narrated, in order (adding the first aisle/item the full way,
    // then the rest briskly).
    expect(steps.map((s) => s.title), [
      'intro',
      'addAisle',
      'nameAisle',
      'confirmAisle',
      'restAisles',
      'typeItem',
      'tapAdd',
      'restItems',
      'check',
      'complete',
      'reveal',
      'done',
    ]);
    // Cleaned up.
    expect(await stores.mostUsedStore(), isNull);
  });

  test('skipping stops early and still deletes the demo store', () async {
    final nav = _RecordingNav();
    final conductor = DemoConductor(autoAdvance: true);
    // Abort before running: the first step's gate check returns aborted.
    conductor.abort();

    await build(nav, conductor, <DemoStep>[]).run();

    expect(await stores.mostUsedStore(), isNull);
    expect(nav.calls.last, 'back');
  });

  test('trip 1 teaches a walk order that sorts a later list', () async {
    // Mirrors the controller's trip-1 teaching loop through the real
    // repositories, then asserts a fresh list sorts into the learned order —
    // the payoff the demo's trip 2 shows. (run()'s cleanup deletes the store,
    // so this drives the repos directly to inspect the result.)
    final zones = DriftZoneRepository(db);
    final catalog = DriftCatalogRepository(db);
    final lists = DriftListRepository(db);
    const learning = LearningService();

    final store = await stores.createStore('Demo Market');
    final zoneByName = {
      for (final name in _strings.zones)
        name: await zones.createZone(storeId: store.id, name: name),
    };

    final list1 = await lists.createList(store.id);
    for (final (itemName, zoneName) in _strings.items.reversed) {
      final item = await catalog.upsertItem(itemName);
      await lists.addEntry(
          listId: list1.id, catalogItemId: item.id, zoneId: zoneByName[zoneName]!.id);
    }
    final taught = await lists.watchEntries(list1.id).first;
    final byName = {for (final e in taught) e.itemName: e};
    for (final (name, _) in _strings.items) {
      await lists.setChecked(byName[name]!.entryId, true);
    }
    await lists.completeRun(list1.id);

    final list2 = await lists.createList(store.id);
    for (final (itemName, zoneName) in _strings.items.reversed) {
      final item = await catalog.upsertItem(itemName);
      await lists.addEntry(
          listId: list2.id, catalogItemId: item.id, zoneId: zoneByName[zoneName]!.id);
    }
    final entries = await lists.watchEntries(list2.id).first;
    expect(entries.every((e) => e.observations.isNotEmpty), isTrue);

    final order = learning.orderEntries(
      entries
          .map((e) => EntryInput(
                entryId: e.entryId,
                zoneId: e.zoneId,
                zoneSeedOrder: e.zoneSeedOrder,
                insertionIndex: e.insertionIndex,
                observations: e.observations,
              ))
          .toList(),
      _strings.zones.length,
    );
    final byId = {for (final e in entries) e.entryId: e};
    expect([for (final id in order) byId[id]!.itemName],
        ['Bananas', 'Bread', 'Milk', 'Eggs']);
  });
}
