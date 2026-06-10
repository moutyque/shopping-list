import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/core/learning/learning_models.dart';
import 'package:shopping_list/core/learning/learning_service.dart';

void main() {
  const service = LearningService(windowSize: 15);

  group('normalize', () {
    test('maps the slot midpoint into (0, 1)', () {
      // 4 items: ordinals 0..3 -> 0.125, 0.375, 0.625, 0.875
      expect(service.normalize(0, 4), closeTo(0.125, 1e-9));
      expect(service.normalize(3, 4), closeTo(0.875, 1e-9));
    });

    test('a single checked item maps to 0.5', () {
      expect(service.normalize(0, 1), closeTo(0.5, 1e-9));
    });

    test('is comparable across different list lengths', () {
      // First-picked stays near the start regardless of list size.
      expect(service.normalize(0, 4), lessThan(0.3));
      expect(service.normalize(0, 20), lessThan(0.1));
    });

    test('rejects invalid input', () {
      expect(() => service.normalize(0, 0), throwsArgumentError);
      expect(() => service.normalize(-1, 4), throwsArgumentError);
      expect(() => service.normalize(4, 4), throwsArgumentError);
    });
  });

  group('median', () {
    test('odd count returns the middle value', () {
      expect(service.median([0.2, 0.9, 0.5]), closeTo(0.5, 1e-9));
    });

    test('even count averages the two middle values', () {
      expect(service.median([0.2, 0.4, 0.6, 0.8]), closeTo(0.5, 1e-9));
    });

    test('does not mutate the input list', () {
      final input = [0.9, 0.1, 0.5];
      service.median(input);
      expect(input, [0.9, 0.1, 0.5]);
    });

    test('throws on empty input', () {
      expect(() => service.median([]), throwsArgumentError);
    });

    test('resists a single outlier (1 change out of 10)', () {
      // Nine runs say "early" (~0.1), one odd run says "late" (0.9).
      final obs = [
        0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, // 9 consistent
        0.9, // 1 outlier
      ];
      expect(service.median(obs), closeTo(0.1, 1e-9));
    });
  });

  group('mergeObservation', () {
    test('appends to the end', () {
      expect(service.mergeObservation([0.1, 0.2], 0.3), [0.1, 0.2, 0.3]);
    });

    test('evicts the oldest beyond the window size', () {
      const small = LearningService(windowSize: 3);
      expect(small.mergeObservation([0.1, 0.2, 0.3], 0.4), [0.2, 0.3, 0.4]);
    });

    test('does not mutate the input window', () {
      final window = [0.1, 0.2];
      service.mergeObservation(window, 0.3);
      expect(window, [0.1, 0.2]);
    });
  });

  group('deriveZoneOrder', () {
    test('cold start falls back to seed order', () {
      final entries = [
        const EntryInput(entryId: 1, zoneId: 30, zoneSeedOrder: 2, insertionIndex: 0),
        const EntryInput(entryId: 2, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 1),
        const EntryInput(entryId: 3, zoneId: 20, zoneSeedOrder: 1, insertionIndex: 2),
      ];
      final order = service.deriveZoneOrder(entries, 3).map((z) => z.zoneId).toList();
      expect(order, [10, 20, 30]);
    });

    test('learned zones order by mean member position', () {
      // Zone 10 items picked late (~0.8), zone 20 items picked early (~0.2),
      // even though zone 10 has the lower seed order.
      final entries = [
        const EntryInput(
            entryId: 1, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 0,
            observations: [0.8, 0.8, 0.8]),
        const EntryInput(
            entryId: 2, zoneId: 20, zoneSeedOrder: 1, insertionIndex: 1,
            observations: [0.2, 0.2, 0.2]),
      ];
      final order = service.deriveZoneOrder(entries, 2).map((z) => z.zoneId).toList();
      expect(order, [20, 10]);
    });
  });

  group('orderEntries', () {
    test('cold start: zone seed order, then insertion order within a zone', () {
      final entries = [
        // Zone 20 (seed 1)
        const EntryInput(entryId: 1, zoneId: 20, zoneSeedOrder: 1, insertionIndex: 0),
        // Zone 10 (seed 0), two items
        const EntryInput(entryId: 2, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 1),
        const EntryInput(entryId: 3, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 2),
      ];
      expect(service.orderEntries(entries, 2), [2, 3, 1]);
    });

    test('learned order overrides seed order', () {
      // Item in zone 10 is consistently picked last; zone 20 first.
      final entries = [
        const EntryInput(
            entryId: 1, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 0,
            observations: [0.9, 0.9, 0.9]),
        const EntryInput(
            entryId: 2, zoneId: 20, zoneSeedOrder: 1, insertionIndex: 1,
            observations: [0.1, 0.1, 0.1]),
      ];
      expect(service.orderEntries(entries, 2), [2, 1]);
    });

    test('within a zone, learned items sort by median; new items go last', () {
      final entries = [
        // All zone 10. Item A picked mid, item B picked early, item C is new.
        const EntryInput(
            entryId: 1, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 0,
            observations: [0.6, 0.6]),
        const EntryInput(
            entryId: 2, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 1,
            observations: [0.2, 0.2]),
        const EntryInput(entryId: 3, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 2),
      ];
      // B (0.2) then A (0.6) then new C.
      expect(service.orderEntries(entries, 1), [2, 1, 3]);
    });

    test('a single odd run does not flip a well-established order', () {
      // Item 1 established early (eight 0.1s + one 0.9 outlier) -> median 0.1.
      // Item 2 established late (0.9s) -> median 0.9. Same zone.
      final entries = [
        const EntryInput(
            entryId: 1, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 0,
            observations: [0.1, 0.1, 0.1, 0.1, 0.9, 0.1, 0.1, 0.1, 0.1]),
        const EntryInput(
            entryId: 2, zoneId: 10, zoneSeedOrder: 0, insertionIndex: 1,
            observations: [0.9, 0.9, 0.9, 0.9, 0.9]),
      ];
      expect(service.orderEntries(entries, 1), [1, 2]);
    });
  });
}
