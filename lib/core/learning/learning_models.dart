/*
 * Pure value objects consumed by [LearningService].
 *
 * These are deliberately decoupled from Drift / persistence so the learning
 * core can be unit-tested in isolation and reused unchanged when the Phase-2
 * remote backend is added.
 */

/// One item as it appears on a list, with everything the learning core needs
/// to decide where it belongs in the walk order.
class EntryInput {
  /// Stable identifier for the list entry (used to report the resulting order).
  final int entryId;

  /// The zone this item is placed in for the current store.
  final int zoneId;

  /// The user-defined baseline order of [zoneId] (0-based). Used as a fallback
  /// for cold-start, before any runs have been recorded.
  final int zoneSeedOrder;

  /// Order in which the user added this entry to the list (0-based). Final,
  /// deterministic tiebreak.
  final int insertionIndex;

  /// Rolling window of normalized (0..1) pick positions observed for this
  /// (store, item) across past runs, most-recent last. Empty = no history.
  final List<double> observations;

  const EntryInput({
    required this.entryId,
    required this.zoneId,
    required this.zoneSeedOrder,
    required this.insertionIndex,
    this.observations = const [],
  });
}

/// A zone with its derived statistics, returned by
/// [LearningService.deriveZoneOrder].
class ZoneRank {
  final int zoneId;

  /// Mean of member-item learned positions, or null when no member item has
  /// any history yet.
  final double? learnedPosition;

  const ZoneRank({required this.zoneId, required this.learnedPosition});
}
