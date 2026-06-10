import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/app/providers.dart';
import 'package:shopping_list/data/db/app_database.dart';
import 'package:shopping_list/data/repositories/repositories.dart';
import 'package:shopping_list/features/stores/stores_screen.dart';

import '../support/fake_onboarding.dart';

/*
 * Drives StoresScreen against fake repositories so the cart action, rename
 * dialog, and launch auto-open can be verified without a real database.
 */

class FakeStoreRepository implements StoreRepository {
  final List<Store> _stores;
  Store? mostUsed;
  final renames = <(int, String)>[];

  FakeStoreRepository(this._stores, {this.mostUsed});

  @override
  Stream<List<Store>> watchStores() => Stream.value(_stores);

  @override
  Future<Store?> mostUsedStore() async => mostUsed;

  @override
  Future<void> renameStore(int storeId, String name) async =>
      renames.add((storeId, name));

  @override
  Future<void> deleteStore(int storeId) async =>
      _stores.removeWhere((s) => s.id == storeId);

  @override
  Future<Store> createStore(String name) => throw UnimplementedError();
  @override
  Future<Store?> getStore(int id) async {
    for (final s in _stores) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class FakeListRepository implements ListRepository {
  @override
  Future<ShoppingList?> activeList(int storeId) async =>
      ShoppingList(id: 1, storeId: storeId, createdAt: DateTime(2026), status: 'active', viewMode: 'grouped');

  @override
  Stream<List<EntryView>> watchEntries(int listId) => Stream.value(const []);

  @override
  Future<ShoppingList> createList(int storeId) => throw UnimplementedError();
  @override
  Stream<ShoppingList?> watchList(int listId) => const Stream.empty();
  @override
  Future<void> setViewMode(int listId, String viewMode) async {}
  @override
  Future<void> completeRun(int listId) async {}
  @override
  Future<void> addEntry(
          {required int listId,
          required int catalogItemId,
          required int zoneId,
          int? qty,
          String? note}) =>
      throw UnimplementedError();
  @override
  Future<void> updateEntry({required int entryId, int? qty, String? note}) =>
      throw UnimplementedError();
  @override
  Future<void> removeEntry(int entryId) => throw UnimplementedError();
  @override
  Future<void> setChecked(int entryId, bool checked) async {}
}

void main() {
  const store = Store(id: 7, name: 'Carrefour');

  Future<FakeStoreRepository> pump(WidgetTester tester, {Store? mostUsed}) async {
    final storeRepo = FakeStoreRepository([store], mostUsed: mostUsed);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeRepositoryProvider.overrideWithValue(storeRepo),
        listRepositoryProvider.overrideWithValue(FakeListRepository()),
        onboardingProvider.overrideWithValue(FakeOnboardingStore()),
      ],
      child: const MaterialApp(home: StoresScreen()),
    ));
    await tester.pumpAndSettle();
    return storeRepo;
  }

  testWidgets('cart icon opens Shop mode for the store', (tester) async {
    await pump(tester); // mostUsed null -> no auto-open

    await tester.tap(find.byIcon(Icons.shopping_cart_checkout));
    await tester.pumpAndSettle();

    // ShoppingScreen shows its Grouped/Walk-order toggle.
    expect(find.text('Walk order'), findsOneWidget);
  });

  testWidgets('rename icon opens a dialog and renames the store',
      (tester) async {
    final repo = await pump(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Rename store'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Carrefour City');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.renames, [(7, 'Carrefour City')]);
  });

  testWidgets('auto-opens the most-used store on launch (build list)',
      (tester) async {
    await pump(tester, mostUsed: store);

    // Auto-open pushes BuildListScreen, whose search field is visible.
    expect(find.text('Add an item…'), findsOneWidget);
  });
}
