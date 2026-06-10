import 'package:drift/drift.dart';

part 'app_database.g.dart';

/*
 * Drift schema for the local-first store.
 *
 * Everything is keyed per store so multi-store learning stays isolated. The
 * learned ordering for an item in a store lives in [Placements] as a small
 * rolling window of normalized observations (serialized via [_DoubleListConverter]).
 */

/// Serializes a rolling window of normalized positions as a comma-separated
/// string. Small and append-only, so a TEXT column is plenty.
class _DoubleListConverter extends TypeConverter<List<double>, String> {
  const _DoubleListConverter();

  @override
  List<double> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    return fromDb.split(',').map(double.parse).toList();
  }

  @override
  String toSql(List<double> value) => value.join(',');
}

class Stores extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

class Zones extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get storeId => integer().references(Stores, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();

  /// User-defined baseline order, used until learning has data.
  IntColumn get seedOrder => integer()();
}

class CatalogItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

class Placements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get storeId => integer().references(Stores, #id, onDelete: KeyAction.cascade)();
  IntColumn get catalogItemId => integer().references(CatalogItems, #id, onDelete: KeyAction.cascade)();
  IntColumn get zoneId => integer().references(Zones, #id, onDelete: KeyAction.cascade)();
  TextColumn get observations => text().map(const _DoubleListConverter()).withDefault(const Constant(''))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {storeId, catalogItemId},
      ];
}

class ShoppingLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get storeId => integer().references(Stores, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  /// 'active' or 'completed'.
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// 'grouped' or 'walk'.
  TextColumn get viewMode => text().withDefault(const Constant('grouped'))();
}

class ListEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get listId => integer().references(ShoppingLists, #id, onDelete: KeyAction.cascade)();
  IntColumn get catalogItemId => integer().references(CatalogItems, #id, onDelete: KeyAction.cascade)();
  IntColumn get qty => integer().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();

  /// Order in which this entry was checked off during the run (null = skipped).
  IntColumn get pickedOrdinal => integer().nullable()();

  /// Order the entry was added to the list (stable tiebreak for sorting).
  IntColumn get insertionIndex => integer()();
}

@DriftDatabase(
  tables: [Stores, Zones, CatalogItems, Placements, ShoppingLists, ListEntries],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
