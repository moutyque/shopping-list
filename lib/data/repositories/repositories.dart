import '../db/app_database.dart';

/*
 * Storage-agnostic repository interfaces. v1 has Drift-backed implementations
 * only; Phase 2 plugs in a local+remote implementation behind these same
 * interfaces with no UI changes.
 *
 * Drift's generated immutable row classes (Store, Zone, CatalogItem, ...) are
 * reused as read models to avoid mapping boilerplate.
 */

/// A catalog item matched by autocomplete, with its usual zone for the current
/// store (null if it has never been placed there) and how often it's been used.
class CatalogSuggestion {
  final CatalogItem item;
  final int? zoneId;
  final int usageCount;

  const CatalogSuggestion({
    required this.item,
    required this.zoneId,
    required this.usageCount,
  });
}

/// A list entry joined with everything the UI and the learning core need.
class EntryView {
  final int entryId;
  final int catalogItemId;
  final String itemName;
  final int zoneId;
  final String zoneName;
  final String? zoneIcon;
  final int zoneSeedOrder;
  final int? qty;
  final String? note;
  final bool checked;
  final int? pickedOrdinal;
  final int insertionIndex;

  /// Rolling window of normalized observations for this (store, item).
  final List<double> observations;

  const EntryView({
    required this.entryId,
    required this.catalogItemId,
    required this.itemName,
    required this.zoneId,
    required this.zoneName,
    required this.zoneIcon,
    required this.zoneSeedOrder,
    required this.qty,
    required this.note,
    required this.checked,
    required this.pickedOrdinal,
    required this.insertionIndex,
    required this.observations,
  });
}

abstract class StoreRepository {
  Stream<List<Store>> watchStores();
  Future<Store> createStore(String name);
  Future<Store?> getStore(int id);

  /// Renames a store in place.
  Future<void> renameStore(int storeId, String name);

  /// The store to open by default on launch: the only store if there is one,
  /// otherwise the one with the most completed runs (ties broken by name).
  /// Null when there are no stores.
  Future<Store?> mostUsedStore();
}

abstract class ZoneRepository {
  Stream<List<Zone>> watchZones(int storeId);
  Future<Zone> createZone({required int storeId, required String name, String? icon});
  Future<void> renameZone(int zoneId, String name);

  /// Persists a new baseline order for the store's zones.
  Future<void> reorderZones(List<int> orderedZoneIds);
}

abstract class CatalogRepository {
  /// Catalog items whose name contains [query], each with its usual zone for
  /// [storeId]. Empty [query] returns the most-used items.
  Future<List<CatalogSuggestion>> suggest(int storeId, String query);

  /// Finds an existing item by exact (case-insensitive) name or creates one.
  Future<CatalogItem> upsertItem(String name);

  /// Sets the zone an item lives in for a store (its "usual zone"), creating
  /// the placement if there isn't one yet. Reflected on the item's list row and
  /// in future suggestions for that store.
  Future<void> setItemZone({
    required int storeId,
    required int catalogItemId,
    required int zoneId,
  });
}

abstract class ListRepository {
  Future<ShoppingList> createList(int storeId);

  /// The store's most recent in-progress (active) list, or null if the store
  /// has none yet or its last list was completed. Used to resume a list rather
  /// than start an empty one each time the store is reopened.
  Future<ShoppingList?> activeList(int storeId);

  Stream<ShoppingList?> watchList(int listId);
  Future<void> setViewMode(int listId, String viewMode);

  /// All entries on the list, joined with catalog/zone/placement data. Caller
  /// orders them via the learning core.
  Stream<List<EntryView>> watchEntries(int listId);

  Future<void> addEntry({
    required int listId,
    required int catalogItemId,
    required int zoneId,
    int? qty,
    String? note,
  });

  Future<void> updateEntry({required int entryId, int? qty, String? note});

  Future<void> removeEntry(int entryId);

  /// Toggles checked state, assigning/clearing the pick ordinal so the run
  /// records the real pick sequence.
  Future<void> setChecked(int entryId, bool checked);

  /// Marks the list completed and feeds each checked item's normalized pick
  /// position into its placement window (the learning signal).
  Future<void> completeRun(int listId);
}
