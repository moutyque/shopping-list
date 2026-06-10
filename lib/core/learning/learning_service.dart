import 'learning_models.dart';

/*
 * The statistical heart of the app.
 *
 * Turns the raw history of past shopping runs into a stable "walk order" for a
 * store. The order is an aggregate (median) of recent observations, so a
 * one-off reordering is a single low-weight data point and the most recurring
 * order keeps winning.
 *
 * Every method here is pure (no I/O, no Flutter) so the behaviour is fully
 * unit-testable.
 */
class LearningService {
  /// How many recent observations to keep per (store, item). Older ones are
  /// evicted, so the learned order tracks how you shop *now*.
  final int windowSize;

  const LearningService({this.windowSize = 15});

  /// Maps a 0-based check-off ordinal to a normalized position in (0, 1).
  ///
  /// Uses the midpoint of the item's slot — `(ordinal + 0.5) / total` — so
  /// lists of different lengths are comparable and a single item maps to 0.5
  /// rather than an extreme.
  double normalize(int pickedOrdinal, int totalChecked) {
    if (totalChecked <= 0) {
      throw ArgumentError.value(totalChecked, 'totalChecked', 'must be > 0');
    }
    if (pickedOrdinal < 0 || pickedOrdinal >= totalChecked) {
      throw ArgumentError.value(
          pickedOrdinal, 'pickedOrdinal', 'must be in [0, $totalChecked)');
    }
    return (pickedOrdinal + 0.5) / totalChecked;
  }

  /// Median of [values]. Robust to a single outlier, which is what keeps the
  /// "1 change out of 10" from flipping the order.
  ///
  /// Throws [ArgumentError] on an empty list.
  double median(List<double> values) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Appends [value] to [window], keeping only the most recent [windowSize].
  List<double> mergeObservation(List<double> window, double value) {
    final merged = [...window, value];
    if (merged.length <= windowSize) return merged;
    return merged.sublist(merged.length - windowSize);
  }

  /// The learned (median) position of an item, or null when it has no history.
  double? _itemLearned(EntryInput e) =>
      e.observations.isEmpty ? null : median(e.observations);

  /// Derives zone order from member-item learning. A zone's position is the
  /// mean of its items' learned (median) positions; zones with no history yet
  /// fall back to their normalized seed order. Result is sorted into walk
  /// order.
  List<ZoneRank> deriveZoneOrder(List<EntryInput> entries, int zoneCount) {
    final seedDenom = (zoneCount - 1) < 1 ? 1 : (zoneCount - 1);

    // Group entries by zone, preserving seed order per zone.
    final learnedByZone = <int, List<double>>{};
    final seedByZone = <int, int>{};
    for (final e in entries) {
      seedByZone[e.zoneId] = e.zoneSeedOrder;
      final learned = _itemLearned(e);
      if (learned != null) {
        (learnedByZone[e.zoneId] ??= []).add(learned);
      }
    }

    final ranks = seedByZone.entries.map((entry) {
      final zoneId = entry.key;
      final learnedList = learnedByZone[zoneId];
      final learned = (learnedList == null || learnedList.isEmpty)
          ? null
          : learnedList.reduce((a, b) => a + b) / learnedList.length;
      return _ScoredZone(
        zoneId: zoneId,
        learned: learned,
        sortKey: learned ?? (entry.value / seedDenom),
        seedOrder: entry.value,
      );
    }).toList();

    ranks.sort((a, b) {
      final byKey = a.sortKey.compareTo(b.sortKey);
      return byKey != 0 ? byKey : a.seedOrder.compareTo(b.seedOrder);
    });

    return ranks
        .map((z) => ZoneRank(zoneId: z.zoneId, learnedPosition: z.learned))
        .toList();
  }

  /// Orders list entries into walk order: by derived zone order, then within
  /// each zone by item learned position (cold-start items fall back to
  /// insertion order, placed after learned items). Returns entry ids.
  List<int> orderEntries(List<EntryInput> entries, int zoneCount) {
    final zoneOrder = deriveZoneOrder(entries, zoneCount);
    final zoneRank = <int, int>{
      for (var i = 0; i < zoneOrder.length; i++) zoneOrder[i].zoneId: i,
    };

    final sorted = [...entries]..sort((a, b) {
        final byZone = zoneRank[a.zoneId]!.compareTo(zoneRank[b.zoneId]!);
        if (byZone != 0) return byZone;

        final la = _itemLearned(a);
        final lb = _itemLearned(b);
        // Learned items come first, ordered by their median position.
        if (la != null && lb != null) {
          final byMedian = la.compareTo(lb);
          return byMedian != 0
              ? byMedian
              : a.insertionIndex.compareTo(b.insertionIndex);
        }
        if (la != null) return -1;
        if (lb != null) return 1;
        // Both new: keep insertion order.
        return a.insertionIndex.compareTo(b.insertionIndex);
      });

    return sorted.map((e) => e.entryId).toList();
  }
}

class _ScoredZone {
  final int zoneId;
  final double? learned;
  final double sortKey;
  final int seedOrder;

  const _ScoredZone({
    required this.zoneId,
    required this.learned,
    required this.sortKey,
    required this.seedOrder,
  });
}
