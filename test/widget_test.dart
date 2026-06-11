import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/app/providers.dart';
import 'package:shopping_list/data/db/app_database.dart';
import 'package:shopping_list/data/repositories/repositories.dart';
import 'package:shopping_list/features/shopping/shopping_screen.dart';
import 'package:shopping_list/l10n/l10n.dart';

import 'support/fake_onboarding.dart';

/*
 * Widget tests drive the screen through a fake repository with a controlled
 * stream — no real database, so there is no real-async I/O to hang on. The DB
 * path is covered by the repository integration tests.
 */

EntryView _entry({
  required int id,
  required String name,
  required int zoneId,
  required String zoneName,
  required int zoneSeed,
  bool checked = false,
  List<double> observations = const [],
}) {
  return EntryView(
    entryId: id,
    catalogItemId: id,
    itemName: name,
    zoneId: zoneId,
    zoneName: zoneName,
    zoneIcon: null,
    zoneSeedOrder: zoneSeed,
    qty: null,
    note: null,
    checked: checked,
    pickedOrdinal: null,
    insertionIndex: id,
    observations: observations,
  );
}

class FakeListRepository implements ListRepository {
  final _controller = StreamController<List<EntryView>>.broadcast();
  List<EntryView> _current;

  FakeListRepository(this._current);

  @override
  Stream<List<EntryView>> watchEntries(int listId) async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> setChecked(int entryId, bool checked) async {
    _current = [
      for (final e in _current)
        e.entryId == entryId ? _copyChecked(e, checked) : e,
    ];
    _controller.add(_current);
  }

  EntryView _copyChecked(EntryView e, bool checked) => EntryView(
        entryId: e.entryId,
        catalogItemId: e.catalogItemId,
        itemName: e.itemName,
        zoneId: e.zoneId,
        zoneName: e.zoneName,
        zoneIcon: e.zoneIcon,
        zoneSeedOrder: e.zoneSeedOrder,
        qty: e.qty,
        note: e.note,
        checked: checked,
        pickedOrdinal: e.pickedOrdinal,
        insertionIndex: e.insertionIndex,
        observations: e.observations,
      );

  @override
  Future<void> setViewMode(int listId, String viewMode) async {}

  @override
  Future<void> completeRun(int listId) async {}

  // Unused by the shopping screen.
  @override
  Future<ShoppingList?> activeList(int storeId) => throw UnimplementedError();
  @override
  Future<ShoppingList> createList(int storeId) => throw UnimplementedError();
  @override
  Stream<ShoppingList?> watchList(int listId) => const Stream.empty();
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
}

void main() {
  const store = Store(id: 1, name: 'Carrefour');

  late FakeListRepository repo;

  setUp(() {
    repo = FakeListRepository([
      // Cold start: order should follow zone seed (Produce 0 before Dairy 1),
      // regardless of the list order here.
      _entry(id: 10, name: 'Milk', zoneId: 2, zoneName: 'Dairy', zoneSeed: 1),
      _entry(id: 11, name: 'Bananas', zoneId: 1, zoneName: 'Produce', zoneSeed: 0),
    ]);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        listRepositoryProvider.overrideWithValue(repo),
        onboardingProvider.overrideWithValue(FakeOnboardingStore()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShoppingScreen(listId: 1, store: store),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders items and zone headers in grouped view', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Bananas'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('PRODUCE'), findsOneWidget);
    expect(find.text('DAIRY'), findsOneWidget);
    expect(find.text('0 of 2 picked'), findsOneWidget);
  });

  testWidgets('walk-order view drops headers and numbers the items',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Walk order'));
    await tester.pumpAndSettle();

    expect(find.text('PRODUCE'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('checking an item updates the picked counter', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 picked'), findsOneWidget);
  });
}
