import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../core/learning/learning_service.dart';
import '../db/app_database.dart';
import 'repositories.dart';

/*
 * Drift-backed implementations of the repository interfaces. All ordering math
 * is delegated to [LearningService]; these classes only move data.
 */

class DriftStoreRepository implements StoreRepository {
  final AppDatabase db;
  DriftStoreRepository(this.db);

  @override
  Stream<List<Store>> watchStores() =>
      (db.select(db.stores)..orderBy([(s) => OrderingTerm.asc(s.name)])).watch();

  @override
  Future<Store> createStore(String name) =>
      db.into(db.stores).insertReturning(StoresCompanion.insert(name: name));

  @override
  Future<Store?> getStore(int id) =>
      (db.select(db.stores)..where((s) => s.id.equals(id))).getSingleOrNull();

  @override
  Future<void> renameStore(int storeId, String name) =>
      (db.update(db.stores)..where((s) => s.id.equals(storeId)))
          .write(StoresCompanion(name: Value(name)));

  @override
  Future<void> deleteStore(int storeId) =>
      (db.delete(db.stores)..where((s) => s.id.equals(storeId))).go();

  @override
  Future<Store?> mostUsedStore() async {
    final all = await (db.select(db.stores)
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .get();
    if (all.length <= 1) return all.isEmpty ? null : all.first;

    final completed = await (db.select(db.shoppingLists)
          ..where((l) => l.status.equals('completed')))
        .get();
    final runsByStore = <int, int>{};
    for (final l in completed) {
      runsByStore[l.storeId] = (runsByStore[l.storeId] ?? 0) + 1;
    }
    all.sort((a, b) {
      final byRuns = (runsByStore[b.id] ?? 0).compareTo(runsByStore[a.id] ?? 0);
      return byRuns != 0 ? byRuns : a.name.compareTo(b.name);
    });
    return all.first;
  }
}

class DriftZoneRepository implements ZoneRepository {
  final AppDatabase db;
  DriftZoneRepository(this.db);

  @override
  Stream<List<Zone>> watchZones(int storeId) => (db.select(db.zones)
        ..where((z) => z.storeId.equals(storeId))
        ..orderBy([(z) => OrderingTerm.asc(z.seedOrder)]))
      .watch();

  @override
  Future<Zone> createZone({
    required int storeId,
    required String name,
    String? icon,
  }) async {
    final existing = await (db.select(db.zones)
          ..where((z) => z.storeId.equals(storeId)))
        .get();
    final nextSeed =
        existing.fold<int>(-1, (m, z) => math.max(m, z.seedOrder)) + 1;
    return db.into(db.zones).insertReturning(ZonesCompanion.insert(
          storeId: storeId,
          name: name,
          icon: Value(icon),
          seedOrder: nextSeed,
        ));
  }

  @override
  Future<void> renameZone(int zoneId, String name) =>
      (db.update(db.zones)..where((z) => z.id.equals(zoneId)))
          .write(ZonesCompanion(name: Value(name)));

  @override
  Future<void> reorderZones(List<int> orderedZoneIds) => db.transaction(() async {
        for (var i = 0; i < orderedZoneIds.length; i++) {
          await (db.update(db.zones)..where((z) => z.id.equals(orderedZoneIds[i])))
              .write(ZonesCompanion(seedOrder: Value(i)));
        }
      });
}

class DriftCatalogRepository implements CatalogRepository {
  final AppDatabase db;
  DriftCatalogRepository(this.db);

  @override
  Future<List<CatalogSuggestion>> suggest(int storeId, String query) async {
    final items = await (db.select(db.catalogItems)
          ..where((c) => query.isEmpty
              ? const Constant(true)
              : c.name.lower().like('%${query.toLowerCase()}%'))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();

    final placements = await (db.select(db.placements)
          ..where((p) => p.storeId.equals(storeId)))
        .get();
    final byItem = {for (final p in placements) p.catalogItemId: p};

    final suggestions = items.map((item) {
      final p = byItem[item.id];
      return CatalogSuggestion(
        item: item,
        zoneId: p?.zoneId,
        usageCount: p?.observations.length ?? 0,
      );
    }).toList()
      ..sort((a, b) {
        final byUse = b.usageCount.compareTo(a.usageCount);
        return byUse != 0 ? byUse : a.item.name.compareTo(b.item.name);
      });

    return suggestions;
  }

  @override
  Future<CatalogItem> upsertItem(String name) async {
    final trimmed = name.trim();
    final existing = await (db.select(db.catalogItems)
          ..where((c) => c.name.lower().equals(trimmed.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing;
    return db
        .into(db.catalogItems)
        .insertReturning(CatalogItemsCompanion.insert(name: trimmed));
  }

  @override
  Future<void> setItemZone({
    required int storeId,
    required int catalogItemId,
    required int zoneId,
  }) async {
    final existing = await (db.select(db.placements)
          ..where((p) =>
              p.storeId.equals(storeId) &
              p.catalogItemId.equals(catalogItemId)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.placements).insert(PlacementsCompanion.insert(
            storeId: storeId,
            catalogItemId: catalogItemId,
            zoneId: zoneId,
          ));
    } else if (existing.zoneId != zoneId) {
      await (db.update(db.placements)..where((p) => p.id.equals(existing.id)))
          .write(PlacementsCompanion(zoneId: Value(zoneId)));
    }
  }
}

class DriftListRepository implements ListRepository {
  final AppDatabase db;
  final LearningService learning;

  DriftListRepository(this.db, {this.learning = const LearningService()});

  @override
  Future<ShoppingList> createList(int storeId) =>
      db.into(db.shoppingLists).insertReturning(ShoppingListsCompanion.insert(
            storeId: storeId,
            createdAt: DateTime.now(),
          ));

  @override
  Future<ShoppingList?> activeList(int storeId) => (db.select(db.shoppingLists)
        ..where((l) => l.storeId.equals(storeId) & l.status.equals('active'))
        ..orderBy([(l) => OrderingTerm.desc(l.createdAt)])
        ..limit(1))
      .getSingleOrNull();

  @override
  Stream<ShoppingList?> watchList(int listId) =>
      (db.select(db.shoppingLists)..where((l) => l.id.equals(listId)))
          .watchSingleOrNull();

  @override
  Future<void> setViewMode(int listId, String viewMode) =>
      (db.update(db.shoppingLists)..where((l) => l.id.equals(listId)))
          .write(ShoppingListsCompanion(viewMode: Value(viewMode)));

  @override
  Stream<List<EntryView>> watchEntries(int listId) {
    final query = db.select(db.listEntries).join([
      innerJoin(db.shoppingLists,
          db.shoppingLists.id.equalsExp(db.listEntries.listId)),
      innerJoin(db.catalogItems,
          db.catalogItems.id.equalsExp(db.listEntries.catalogItemId)),
      innerJoin(
          db.placements,
          db.placements.catalogItemId.equalsExp(db.listEntries.catalogItemId) &
              db.placements.storeId.equalsExp(db.shoppingLists.storeId)),
      innerJoin(db.zones, db.zones.id.equalsExp(db.placements.zoneId)),
    ])
      ..where(db.listEntries.listId.equals(listId));

    return query.watch().map((rows) => rows.map((row) {
          final entry = row.readTable(db.listEntries);
          final item = row.readTable(db.catalogItems);
          final placement = row.readTable(db.placements);
          final zone = row.readTable(db.zones);
          return EntryView(
            entryId: entry.id,
            catalogItemId: entry.catalogItemId,
            itemName: item.name,
            zoneId: zone.id,
            zoneName: zone.name,
            zoneIcon: zone.icon,
            zoneSeedOrder: zone.seedOrder,
            qty: entry.qty,
            note: entry.note,
            checked: entry.checked,
            pickedOrdinal: entry.pickedOrdinal,
            insertionIndex: entry.insertionIndex,
            observations: placement.observations,
          );
        }).toList());
  }

  @override
  Future<void> addEntry({
    required int listId,
    required int catalogItemId,
    required int zoneId,
    int? qty,
    String? note,
  }) async {
    await db.transaction(() async {
      final list = await (db.select(db.shoppingLists)
            ..where((l) => l.id.equals(listId)))
          .getSingle();

      // Ensure a placement exists for this (store, item), recording its zone.
      final placement = await (db.select(db.placements)
            ..where((p) =>
                p.storeId.equals(list.storeId) &
                p.catalogItemId.equals(catalogItemId)))
          .getSingleOrNull();
      if (placement == null) {
        await db.into(db.placements).insert(PlacementsCompanion.insert(
              storeId: list.storeId,
              catalogItemId: catalogItemId,
              zoneId: zoneId,
            ));
      } else if (placement.zoneId != zoneId) {
        await (db.update(db.placements)..where((p) => p.id.equals(placement.id)))
            .write(PlacementsCompanion(zoneId: Value(zoneId)));
      }

      final count = await (db.select(db.listEntries)
            ..where((e) => e.listId.equals(listId)))
          .get();
      await db.into(db.listEntries).insert(ListEntriesCompanion.insert(
            listId: listId,
            catalogItemId: catalogItemId,
            qty: Value(qty),
            note: Value(note),
            insertionIndex: count.length,
          ));
    });
  }

  @override
  Future<void> updateEntry({required int entryId, int? qty, String? note}) =>
      (db.update(db.listEntries)..where((e) => e.id.equals(entryId)))
          .write(ListEntriesCompanion(qty: Value(qty), note: Value(note)));

  @override
  Future<void> removeEntry(int entryId) =>
      (db.delete(db.listEntries)..where((e) => e.id.equals(entryId))).go();

  @override
  Future<void> setChecked(int entryId, bool checked) async {
    final entry = await (db.select(db.listEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingle();

    if (!checked) {
      await (db.update(db.listEntries)..where((e) => e.id.equals(entryId)))
          .write(const ListEntriesCompanion(
        checked: Value(false),
        pickedOrdinal: Value(null),
      ));
      return;
    }

    // Assign the next monotonic pick ordinal so the real pick sequence is kept.
    final checkedEntries = await (db.select(db.listEntries)
          ..where((e) => e.listId.equals(entry.listId) & e.checked.equals(true)))
        .get();
    final nextOrdinal =
        checkedEntries.fold<int>(-1, (m, e) => math.max(m, e.pickedOrdinal ?? -1)) +
            1;

    await (db.update(db.listEntries)..where((e) => e.id.equals(entryId)))
        .write(ListEntriesCompanion(
      checked: const Value(true),
      pickedOrdinal: Value(nextOrdinal),
    ));
  }

  @override
  Future<void> completeRun(int listId) async {
    await db.transaction(() async {
      final list = await (db.select(db.shoppingLists)
            ..where((l) => l.id.equals(listId)))
          .getSingle();

      final picked = await (db.select(db.listEntries)
            ..where((e) => e.listId.equals(listId) & e.checked.equals(true))
            ..orderBy([(e) => OrderingTerm.asc(e.pickedOrdinal)]))
          .get();

      final total = picked.length;
      for (var i = 0; i < total; i++) {
        final norm = learning.normalize(i, total);
        final placement = await (db.select(db.placements)
              ..where((p) =>
                  p.storeId.equals(list.storeId) &
                  p.catalogItemId.equals(picked[i].catalogItemId)))
            .getSingleOrNull();
        if (placement == null) continue;
        final updated = learning.mergeObservation(placement.observations, norm);
        await (db.update(db.placements)..where((p) => p.id.equals(placement.id)))
            .write(PlacementsCompanion(observations: Value(updated)));
      }

      await (db.update(db.shoppingLists)..where((l) => l.id.equals(listId)))
          .write(const ShoppingListsCompanion(status: Value('completed')));
    });
  }
}
