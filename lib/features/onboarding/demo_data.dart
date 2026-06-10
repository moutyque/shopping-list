import '../../data/db/app_database.dart';
import '../../data/repositories/repositories.dart';

/// Result of seeding: the demo store and its ready-to-shop list.
class DemoSeed {
  final Store store;
  final ShoppingList list;
  const DemoSeed(this.store, this.list);
}

const _demoStoreName = 'Demo Market';
const _demoZones = ['Produce', 'Bakery', 'Dairy', 'Frozen'];
const _demoItems = <(String, String)>[
  ('Bananas', 'Produce'),
  ('Apples', 'Produce'),
  ('Bread', 'Bakery'),
  ('Croissants', 'Bakery'),
  ('Milk', 'Dairy'),
  ('Eggs', 'Dairy'),
  ('Frozen pizza', 'Frozen'),
];

/// Creates a fully-populated sample store so a new user immediately sees a real
/// list (items already placed in zones) to explore and shop. Built entirely
/// through the normal repositories, so it exercises the same paths a user would.
Future<DemoSeed> seedDemoStore({
  required StoreRepository stores,
  required ZoneRepository zones,
  required CatalogRepository catalog,
  required ListRepository lists,
}) async {
  final store = await stores.createStore(_demoStoreName);

  final zoneByName = <String, Zone>{};
  for (final name in _demoZones) {
    zoneByName[name] = await zones.createZone(storeId: store.id, name: name);
  }

  final list = await lists.createList(store.id);
  for (final (itemName, zoneName) in _demoItems) {
    final item = await catalog.upsertItem(itemName);
    await lists.addEntry(
      listId: list.id,
      catalogItemId: item.id,
      zoneId: zoneByName[zoneName]!.id,
    );
  }

  return DemoSeed(store, list);
}
