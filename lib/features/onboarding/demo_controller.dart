import 'package:flutter/widgets.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/repositories.dart';
import 'demo_conductor.dart';
import 'demo_data.dart';

/// Screen transitions the demo drives. Abstracted so the controller can be
/// tested without a real Navigator.
abstract class DemoNavigator {
  void openZones(Store store);
  void openBuildList(Store store, ShoppingList list);
  void openShopping(Store store, ShoppingList list);
  void backToStores();
}

/// One narrated beat: a short title and an explanatory line, shown in the
/// overlay card while the matching widget is highlighted.
class DemoStep {
  final String title;
  final String body;
  const DemoStep(this.title, this.body);
}

/// Localized title + body for every step of the guided tour.
class DemoNarration {
  final (String, String) intro;
  final (String, String) addAisle;
  final (String, String) nameAisle;
  final (String, String) confirmAisle;
  final (String, String) restAisles;
  final (String, String) typeItem;
  final (String, String) tapAdd;
  final (String, String) restItems;
  final (String, String) check;
  final (String, String) complete;
  final (String, String) reveal;
  final (String, String) done;

  const DemoNarration({
    required this.intro,
    required this.addAisle,
    required this.nameAisle,
    required this.confirmAisle,
    required this.restAisles,
    required this.typeItem,
    required this.tapAdd,
    required this.restItems,
    required this.check,
    required this.complete,
    required this.reveal,
    required this.done,
  });
}

/// User-paced guided tour of the app's core feature: learning your walk order.
/// The tour auto-performs each action (through the real repositories so the
/// reactive UI updates), but pauses behind a Next button at every step and
/// points the spotlight at the real widget being acted on. It shows the full
/// add-an-aisle and add-an-item process once, adds the rest briskly, shops the
/// list, then proves the learning on a second trip. Pure orchestration
/// (navigation + the conductor are injected), so it is unit-testable.
class DemoController {
  final StoreRepository stores;
  final ZoneRepository zones;
  final CatalogRepository catalog;
  final ListRepository lists;
  final DemoNavigator nav;
  final DemoConductor conductor;
  final DemoStrings strings;
  final DemoNarration narration;
  final void Function(DemoStep) onStep;

  /// Time to let a route-pop animation finish before pushing the next screen,
  /// so two instances of a screen never coexist. Tests pass [Duration.zero].
  final Duration settle;

  DemoController({
    required this.stores,
    required this.zones,
    required this.catalog,
    required this.lists,
    required this.nav,
    required this.conductor,
    required this.strings,
    required this.narration,
    required this.onStep,
    this.settle = const Duration(milliseconds: 700),
  });

  /// Shows [caption], highlights [target] (null dims everything), then waits for
  /// the user to tap Next. Returns false if the tour was skipped meanwhile.
  Future<bool> _step((String, String) caption, GlobalKey? target,
      {bool last = false}) async {
    conductor.target.value = target;
    conductor.isLast.value = last;
    onStep(DemoStep(caption.$1, caption.$2));
    await conductor.waitForNext();
    return !conductor.aborted;
  }

  Future<void> run() async {
    Store? store;
    try {
      if (!await _step(narration.intro, null)) return;

      store = await stores.createStore(strings.storeName);
      nav.openZones(store);
      final zoneByName = <String, Zone>{};
      final firstZone = strings.zones.first;
      final restZones = strings.zones.skip(1).toList();

      // Add the first aisle the full way: tap +, name it, confirm.
      if (!await _step(narration.addAisle, conductor.newZoneFabKey)) return;
      conductor.zoneNameController.text = firstZone;
      conductor.zoneDialogVisible.value = true;
      if (!await _step(narration.nameAisle, conductor.zoneNameFieldKey)) return;
      if (!await _step(narration.confirmAisle, conductor.zoneConfirmKey)) return;
      conductor.zoneDialogVisible.value = false;
      zoneByName[firstZone] =
          await zones.createZone(storeId: store.id, name: firstZone);

      // Add the remaining aisles briskly.
      if (restZones.isNotEmpty) {
        if (!await _step(narration.restAisles, conductor.newZoneFabKey)) return;
        for (final name in restZones) {
          zoneByName[name] =
              await zones.createZone(storeId: store.id, name: name);
        }
      }

      // Build the first list — the items added jumbled (reverse walk order).
      final list1 = await lists.createList(store.id);
      nav.openBuildList(store, list1);
      final jumbled = strings.items.reversed.toList();
      final firstItem = jumbled.first;

      // Add the first item the full way: type it, tap "Add new X".
      conductor.searchController.text = firstItem.$1;
      if (!await _step(narration.typeItem, conductor.searchFieldKey)) return;
      if (!await _step(narration.tapAdd, conductor.addTileKey)) return;
      await _addItem(list1, firstItem, zoneByName);
      conductor.searchController.clear();

      // Add the rest briskly.
      final restItems = jumbled.skip(1).toList();
      if (restItems.isNotEmpty) {
        if (!await _step(narration.restItems, conductor.searchFieldKey)) return;
        for (final item in restItems) {
          await _addItem(list1, item, zoneByName);
        }
      }

      // Shop it: check off in walk order. Highlight the first pick, then the
      // rest as one beat.
      nav.openShopping(store, list1);
      final entries = await lists.watchEntries(list1.id).first;
      final byName = {for (final e in entries) e.itemName: e};
      final walk = strings.items.map((i) => byName[i.$1]).whereType<EntryView>();
      if (walk.isNotEmpty) {
        final first = walk.first;
        if (!await _step(narration.check, conductor.checkboxKey(first.entryId))) {
          return;
        }
        await lists.setChecked(first.entryId, true);
        for (final e in walk.skip(1)) {
          await lists.setChecked(e.entryId, true);
        }
      }

      // Save the run — this is the learning signal.
      if (!await _step(narration.complete, conductor.completeKey)) return;
      await lists.completeRun(list1.id);

      // Trip 2 — the payoff. Same items, added jumbled again (briskly, the
      // process was shown on trip 1); the list opens already in walk order.
      // Reset the stack first so trip 1's screens unmount — otherwise two
      // ShoppingScreens would share the same highlight GlobalKeys.
      final list2 = await lists.createList(store.id);
      for (final item in jumbled) {
        await _addItem(list2, item, zoneByName);
      }
      // Pop trip 1's screens and let the animation finish before opening trip
      // 2's shopping, so the two ShoppingScreens never share highlight keys.
      nav.backToStores();
      await Future<void>.delayed(settle);
      if (conductor.aborted) return;
      nav.openShopping(store, list2);
      if (!await _step(narration.reveal, conductor.bannerKey)) return;

      await _step(narration.done, null, last: true);
    } finally {
      conductor.target.value = null;
      conductor.zoneDialogVisible.value = false;
      nav.backToStores();
      if (store != null) {
        await stores.deleteStore(store.id);
      }
    }
  }

  Future<void> _addItem(ShoppingList list, (String, String) item,
      Map<String, Zone> zoneByName) async {
    final catalogItem = await catalog.upsertItem(item.$1);
    await lists.addEntry(
      listId: list.id,
      catalogItemId: catalogItem.id,
      zoneId: zoneByName[item.$2]!.id,
    );
  }
}
