import '../../data/db/app_database.dart';
import '../../data/repositories/repositories.dart';
import 'demo_data.dart';

/// Screen transitions the demo drives. Abstracted so the controller can be
/// tested without a real Navigator/Overlay.
abstract class DemoNavigator {
  void openBuildList(Store store, ShoppingList list);
  void openZones(Store store);
  void openShopping(Store store, ShoppingList list);
  void backToStores();
}

/// Narration shown in the caption bar as each stage runs.
class DemoCaptions {
  final String creating;
  final String adding;
  final String reordering;
  final String shopping;
  final String done;

  const DemoCaptions({
    required this.creating,
    required this.adding,
    required this.reordering,
    required this.shopping,
    required this.done,
  });
}

/// Autonomous, narrated demo: it creates a demo store, fills a list, reorders
/// aisles, shops it, then deletes the store — all by driving the real
/// repositories on a timer so the reactive UI shows each step happening. Pure
/// orchestration (navigation + captions are injected), so it is unit-testable.
class DemoController {
  final StoreRepository stores;
  final ZoneRepository zones;
  final CatalogRepository catalog;
  final ListRepository lists;
  final DemoNavigator nav;
  final DemoStrings strings;
  final DemoCaptions captions;
  final void Function(String) onCaption;

  /// Delay between micro-steps. Production uses ~0.7s; tests pass [Duration.zero].
  final Duration pace;

  bool _aborted = false;

  DemoController({
    required this.stores,
    required this.zones,
    required this.catalog,
    required this.lists,
    required this.nav,
    required this.strings,
    required this.captions,
    required this.onCaption,
    this.pace = const Duration(milliseconds: 700),
  });

  /// Requests the demo stop at the next checkpoint (Skip button).
  void abort() => _aborted = true;

  Future<void> run() async {
    Store? store;
    try {
      onCaption(captions.creating);
      store = await stores.createStore(strings.storeName);
      final zoneByName = <String, Zone>{};
      for (final name in strings.zones) {
        zoneByName[name] = await zones.createZone(storeId: store.id, name: name);
      }
      final list = await lists.createList(store.id);
      await _beat();
      if (_aborted) return;
      nav.openBuildList(store, list);
      await _beat();

      onCaption(captions.adding);
      for (final (itemName, zoneName) in strings.items) {
        if (_aborted) return;
        final item = await catalog.upsertItem(itemName);
        await lists.addEntry(
          listId: list.id,
          catalogItemId: item.id,
          zoneId: zoneByName[zoneName]!.id,
        );
        await _beat();
      }

      if (_aborted) return;
      onCaption(captions.reordering);
      nav.openZones(store);
      await _beat();
      // Reverse the walk order so the aisles visibly move.
      final current = await zones.watchZones(store.id).first;
      await zones.reorderZones(current.reversed.map((z) => z.id).toList());
      await _beat();
      await _beat();

      if (_aborted) return;
      onCaption(captions.shopping);
      nav.openShopping(store, list);
      await _beat();
      final entries = await lists.watchEntries(list.id).first;
      for (final e in entries) {
        if (_aborted) return;
        await lists.setChecked(e.entryId, true);
        await _beat();
      }

      if (_aborted) return;
      await lists.completeRun(list.id);
      onCaption(captions.done);
      await _beat();
      await _beat();
    } finally {
      nav.backToStores();
      if (store != null) {
        await stores.deleteStore(store.id);
      }
    }
  }

  Future<void> _beat() => Future<void>.delayed(pace);
}
