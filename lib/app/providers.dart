import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/learning/learning_models.dart';
import '../core/learning/learning_service.dart';
import '../data/db/app_database.dart';
import '../data/db/connection.dart';
import '../data/repositories/drift_repositories.dart';
import '../data/repositories/repositories.dart';

/*
 * Dependency wiring. The database provider is overridden in tests with an
 * in-memory instance; everything below depends only on the repository
 * interfaces, so the Phase-2 remote backend can be injected here unchanged.
 */

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = openAppDatabase();
  ref.onDispose(db.close);
  return db;
});

final learningServiceProvider =
    Provider<LearningService>((ref) => const LearningService());

final storeRepositoryProvider = Provider<StoreRepository>(
    (ref) => DriftStoreRepository(ref.watch(databaseProvider)));

final zoneRepositoryProvider = Provider<ZoneRepository>(
    (ref) => DriftZoneRepository(ref.watch(databaseProvider)));

final catalogRepositoryProvider = Provider<CatalogRepository>(
    (ref) => DriftCatalogRepository(ref.watch(databaseProvider)));

final listRepositoryProvider = Provider<ListRepository>((ref) =>
    DriftListRepository(ref.watch(databaseProvider),
        learning: ref.watch(learningServiceProvider)));

// --- Reactive reads ---------------------------------------------------------

final storesProvider =
    StreamProvider<List<Store>>((ref) => ref.watch(storeRepositoryProvider).watchStores());

final zonesProvider = StreamProvider.family<List<Zone>, int>(
    (ref, storeId) => ref.watch(zoneRepositoryProvider).watchZones(storeId));

final listProvider = StreamProvider.family<ShoppingList?, int>(
    (ref, listId) => ref.watch(listRepositoryProvider).watchList(listId));

final entriesProvider = StreamProvider.family<List<EntryView>, int>(
    (ref, listId) => ref.watch(listRepositoryProvider).watchEntries(listId));

/// Entries ordered into walk order via the learning core, paired with the
/// number of zones in the store (needed for the seed-order fallback).
final orderedEntriesProvider =
    Provider.family<List<EntryView>, int>((ref, listId) {
  final entries = ref.watch(entriesProvider(listId)).asData?.value ?? const [];
  if (entries.isEmpty) return const [];
  final learning = ref.watch(learningServiceProvider);
  final zoneCount = entries.map((e) => e.zoneId).toSet().length;
  final order = learning.orderEntries(
    entries
        .map((e) => EntryInput(
              entryId: e.entryId,
              zoneId: e.zoneId,
              zoneSeedOrder: e.zoneSeedOrder,
              insertionIndex: e.insertionIndex,
              observations: e.observations,
            ))
        .toList(),
    zoneCount,
  );
  final byId = {for (final e in entries) e.entryId: e};
  return [for (final id in order) byId[id]!];
});
