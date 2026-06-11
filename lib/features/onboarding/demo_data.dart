import '../../data/db/app_database.dart';
import '../../data/repositories/repositories.dart';

/// Localized names used to seed the demo store, supplied by the caller from the
/// active [AppLocalizations] so the sample data matches the app's language.
class DemoStrings {
  final String storeName;

  /// Zone names in walk order.
  final List<String> zones;

  /// (item name, zone name) — each zone name must be one of [zones].
  final List<(String, String)> items;

  const DemoStrings({
    required this.storeName,
    required this.zones,
    required this.items,
  });
}

/// Result of seeding: the demo store and its ready-to-shop list.
class DemoSeed {
  final Store store;
  final ShoppingList list;
  const DemoSeed(this.store, this.list);
}

/// Creates a fully-populated sample store so a new user immediately sees a real
/// list (items already placed in zones) to explore and shop. Built entirely
/// through the normal repositories, so it exercises the same paths a user would.
Future<DemoSeed> seedDemoStore({
  required DemoStrings strings,
  required StoreRepository stores,
  required ZoneRepository zones,
  required CatalogRepository catalog,
  required ListRepository lists,
}) async {
  final store = await stores.createStore(strings.storeName);

  final zoneByName = <String, Zone>{};
  for (final name in strings.zones) {
    zoneByName[name] = await zones.createZone(storeId: store.id, name: name);
  }

  final list = await lists.createList(store.id);
  for (final (itemName, zoneName) in strings.items) {
    final item = await catalog.upsertItem(itemName);
    await lists.addEntry(
      listId: list.id,
      catalogItemId: item.id,
      zoneId: zoneByName[zoneName]!.id,
    );
  }

  return DemoSeed(store, list);
}
