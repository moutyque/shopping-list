import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/core/learning/learning_models.dart';
import 'package:shopping_list/core/learning/learning_service.dart';
import 'package:shopping_list/data/db/app_database.dart';
import 'package:shopping_list/data/repositories/drift_repositories.dart';

void main() {
  late AppDatabase db;
  late DriftStoreRepository stores;
  late DriftZoneRepository zones;
  late DriftCatalogRepository catalog;
  late DriftListRepository lists;
  const learning = LearningService();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    stores = DriftStoreRepository(db);
    zones = DriftZoneRepository(db);
    catalog = DriftCatalogRepository(db);
    lists = DriftListRepository(db, learning: learning);
  });

  tearDown(() async => db.close());

  // Orders an entry list the way the UI will, via the learning core.
  Future<List<String>> orderedNames(int listId, int zoneCount) async {
    final entries = await lists.watchEntries(listId).first;
    final byId = {for (final e in entries) e.entryId: e};
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
      zoneCount,
    );
    return order.map((id) => byId[id]!.itemName).toList();
  }

  test('cold start orders by zone seed order', () async {
    final store = await stores.createStore('Carrefour');
    final produce = await zones.createZone(storeId: store.id, name: 'Produce');
    final dairy = await zones.createZone(storeId: store.id, name: 'Dairy');

    final bananas = await catalog.upsertItem('Bananas');
    final milk = await catalog.upsertItem('Milk');

    final list = await lists.createList(store.id);
    // Add Milk (Dairy) first, then Bananas (Produce) — input order is reversed
    // from the seed order on purpose.
    await lists.addEntry(listId: list.id, catalogItemId: milk.id, zoneId: dairy.id);
    await lists.addEntry(listId: list.id, catalogItemId: bananas.id, zoneId: produce.id);

    // Produce (seed 0) comes before Dairy (seed 1) despite input order.
    expect(await orderedNames(list.id, 2), ['Bananas', 'Milk']);
  });

  test('a completed run teaches the order for the next list', () async {
    final store = await stores.createStore('Carrefour');
    final produce = await zones.createZone(storeId: store.id, name: 'Produce');
    final dairy = await zones.createZone(storeId: store.id, name: 'Dairy');
    final bananas = await catalog.upsertItem('Bananas');
    final milk = await catalog.upsertItem('Milk');

    // Run 1: pick Milk first, Bananas second (opposite of seed order).
    final run1 = await lists.createList(store.id);
    await lists.addEntry(listId: run1.id, catalogItemId: bananas.id, zoneId: produce.id);
    await lists.addEntry(listId: run1.id, catalogItemId: milk.id, zoneId: dairy.id);
    final r1 = await lists.watchEntries(run1.id).first;
    final r1Milk = r1.firstWhere((e) => e.itemName == 'Milk').entryId;
    final r1Bananas = r1.firstWhere((e) => e.itemName == 'Bananas').entryId;
    await lists.setChecked(r1Milk, true); // picked first
    await lists.setChecked(r1Bananas, true); // picked second
    await lists.completeRun(run1.id);

    // Run 2: add both again (any order) — learned order now wins over seed.
    final run2 = await lists.createList(store.id);
    await lists.addEntry(listId: run2.id, catalogItemId: bananas.id, zoneId: produce.id);
    await lists.addEntry(listId: run2.id, catalogItemId: milk.id, zoneId: dairy.id);

    expect(await orderedNames(run2.id, 2), ['Milk', 'Bananas']);
  });

  test('reopening a store resumes its active list with the items still on it', () async {
    final store = await stores.createStore('Carrefour');
    final dairy = await zones.createZone(storeId: store.id, name: 'Dairy');
    final milk = await catalog.upsertItem('Milk');

    final list = await lists.createList(store.id);
    await lists.addEntry(listId: list.id, catalogItemId: milk.id, zoneId: dairy.id);

    // Reopening the store must resume the same active list, not start fresh.
    final resumed = await lists.activeList(store.id);
    expect(resumed, isNotNull);
    expect(resumed!.id, list.id);

    final entries = await lists.watchEntries(resumed.id).first;
    expect(entries.map((e) => e.itemName).toList(), ['Milk']);
  });

  test('a completed run is not resumed', () async {
    final store = await stores.createStore('Carrefour');
    final list = await lists.createList(store.id);
    await lists.completeRun(list.id);

    expect(await lists.activeList(store.id), isNull);
  });

  test('renameStore changes the name in place', () async {
    final store = await stores.createStore('Carrefour');
    await stores.renameStore(store.id, 'Carrefour City');
    expect((await stores.getStore(store.id))!.name, 'Carrefour City');
  });

  test('mostUsedStore is null with no stores', () async {
    expect(await stores.mostUsedStore(), isNull);
  });

  test('mostUsedStore returns the only store', () async {
    final store = await stores.createStore('Carrefour');
    expect((await stores.mostUsedStore())!.id, store.id);
  });

  test('mostUsedStore picks the store with the most completed runs', () async {
    final a = await stores.createStore('Aldi');
    final b = await stores.createStore('Biocoop');

    // Aldi: 1 completed run. Biocoop: 2. Biocoop wins despite alphabetical order.
    await lists.completeRun((await lists.createList(a.id)).id);
    await lists.completeRun((await lists.createList(b.id)).id);
    await lists.completeRun((await lists.createList(b.id)).id);

    expect((await stores.mostUsedStore())!.id, b.id);
  });

  test('mostUsedStore breaks ties alphabetically', () async {
    await stores.createStore('Biocoop');
    final a = await stores.createStore('Aldi');
    // No runs anywhere: tie at 0, so the alphabetically-first store wins.
    expect((await stores.mostUsedStore())!.id, a.id);
  });

  test('placement remembers an item\'s usual zone (suggestions)', () async {
    final store = await stores.createStore('Carrefour');
    final dairy = await zones.createZone(storeId: store.id, name: 'Dairy');
    final milk = await catalog.upsertItem('Milk');

    final list = await lists.createList(store.id);
    await lists.addEntry(listId: list.id, catalogItemId: milk.id, zoneId: dairy.id);

    final suggestions = await catalog.suggest(store.id, 'mil');
    expect(suggestions, hasLength(1));
    expect(suggestions.first.item.name, 'Milk');
    expect(suggestions.first.zoneId, dairy.id);
  });

  test('setItemZone reassigns an item to a new zone', () async {
    final store = await stores.createStore('Carrefour');
    final produce = await zones.createZone(storeId: store.id, name: 'Produce');
    final dairy = await zones.createZone(storeId: store.id, name: 'Dairy');
    final milk = await catalog.upsertItem('Milk');

    final list = await lists.createList(store.id);
    // Placed (wrongly) in Produce to begin with.
    await lists.addEntry(listId: list.id, catalogItemId: milk.id, zoneId: produce.id);
    expect((await lists.watchEntries(list.id).first).single.zoneName, 'Produce');

    await catalog.setItemZone(
        storeId: store.id, catalogItemId: milk.id, zoneId: dairy.id);

    // The list row and the suggestion both follow the item to Dairy.
    expect((await lists.watchEntries(list.id).first).single.zoneName, 'Dairy');
    expect((await catalog.suggest(store.id, 'milk')).single.zoneId, dairy.id);
  });

  test('upsertItem is case-insensitive and does not duplicate', () async {
    final a = await catalog.upsertItem('Milk');
    final b = await catalog.upsertItem('  milk ');
    expect(a.id, b.id);
  });

  test('reorderZones persists a new seed order', () async {
    final store = await stores.createStore('Carrefour');
    final produce = await zones.createZone(storeId: store.id, name: 'Produce');
    final dairy = await zones.createZone(storeId: store.id, name: 'Dairy');

    await zones.reorderZones([dairy.id, produce.id]);

    final ordered = await zones.watchZones(store.id).first;
    expect(ordered.map((z) => z.name).toList(), ['Dairy', 'Produce']);
  });
}
