import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/data/db/app_database.dart';
import 'package:shopping_list/data/repositories/drift_repositories.dart';
import 'package:shopping_list/features/onboarding/demo_data.dart';

void main() {
  late AppDatabase db;
  late DriftStoreRepository stores;
  late DriftZoneRepository zones;
  late DriftCatalogRepository catalog;
  late DriftListRepository lists;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    stores = DriftStoreRepository(db);
    zones = DriftZoneRepository(db);
    catalog = DriftCatalogRepository(db);
    lists = DriftListRepository(db);
  });

  tearDown(() async => db.close());

  const strings = DemoStrings(
    storeName: 'Demo Market',
    zones: ['Produce', 'Bakery', 'Dairy', 'Frozen'],
    items: [
      ('Bananas', 'Produce'),
      ('Apples', 'Produce'),
      ('Bread', 'Bakery'),
      ('Croissants', 'Bakery'),
      ('Milk', 'Dairy'),
      ('Eggs', 'Dairy'),
      ('Frozen pizza', 'Frozen'),
    ],
  );

  test('seedDemoStore creates a populated, ready-to-shop store', () async {
    final seed = await seedDemoStore(
        strings: strings,
        stores: stores,
        zones: zones,
        catalog: catalog,
        lists: lists);

    // 4 zones in walk order.
    final z = await zones.watchZones(seed.store.id).first;
    expect(z.map((e) => e.name).toList(),
        ['Produce', 'Bakery', 'Dairy', 'Frozen']);

    // 7 items, each joined to a real zone (the join proves placements exist).
    final entries = await lists.watchEntries(seed.list.id).first;
    expect(entries, hasLength(7));
    expect(
      entries.firstWhere((e) => e.itemName == 'Milk').zoneName,
      'Dairy',
    );
    expect(
      entries.firstWhere((e) => e.itemName == 'Bananas').zoneName,
      'Produce',
    );
  });
}
