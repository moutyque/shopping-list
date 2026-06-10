import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../onboarding/coach_marks.dart';
import '../onboarding/onboarding_service.dart';
import '../stores/stores_screen.dart' show promptName;

/// Manage a store's zones: add, rename, and set the baseline (seed) order by
/// dragging. The learned order refines this over time but the seed order is the
/// cold-start fallback.
class ZonesScreen extends ConsumerStatefulWidget {
  final Store store;
  const ZonesScreen({super.key, required this.store});

  @override
  ConsumerState<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends ConsumerState<ZonesScreen> {
  final _fabKey = GlobalKey();
  final _dragKey = GlobalKey();
  final _editKey = GlobalKey();

  /// Coach-marks fire once the list has at least one zone (so the drag/rename
  /// targets exist). With zero zones the empty-state text already explains it.
  bool _coachScheduled = false;

  void _scheduleCoach() {
    if (_coachScheduled) return;
    _coachScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowCoachMarks(context,
          store: ref.read(onboardingProvider),
          seenKey: CoachKeys.zones,
          steps: [
            CoachStep(
              id: 'reorder',
              key: _dragKey,
              text: 'Drag a zone to set the order you walk the store — your '
                  'shopping list follows this order.',
            ),
            CoachStep(
              id: 'rename-zone',
              key: _editKey,
              text: 'Rename an aisle here.',
            ),
            CoachStep(
              id: 'add-zone',
              key: _fabKey,
              align: ContentAlign.top,
              text: 'Add more aisles any time.',
            ),
          ]);
    });
  }

  Future<void> _addZone() async {
    final name = await promptName(context, title: 'New zone');
    if (name == null || name.isEmpty) return;
    await ref
        .read(zoneRepositoryProvider)
        .createZone(storeId: widget.store.id, name: name);
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(zonesProvider(widget.store.id));
    return Scaffold(
      appBar: AppBar(title: Text('${widget.store.name} · zones')),
      floatingActionButton: FloatingActionButton.extended(
        key: _fabKey,
        onPressed: _addZone,
        icon: const Icon(Icons.add),
        label: const Text('Zone'),
      ),
      body: zones.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Add zones like Produce, Bakery, Dairy…\n'
                  'Drag to set the order you usually walk them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _scheduleCoach();
          return ReorderableListView.builder(
            itemCount: list.length,
            onReorderItem: (oldIndex, newIndex) {
              final ids = list.map((z) => z.id).toList();
              final moved = ids.removeAt(oldIndex);
              ids.insert(newIndex, moved);
              ref.read(zoneRepositoryProvider).reorderZones(ids);
            },
            itemBuilder: (context, i) {
              final zone = list[i];
              return ListTile(
                key: ValueKey(zone.id),
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(zone.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: i == 0 ? _editKey : null,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await promptName(context,
                            title: 'Rename zone', initial: zone.name);
                        if (name == null || name.isEmpty) return;
                        await ref
                            .read(zoneRepositoryProvider)
                            .renameZone(zone.id, name);
                      },
                    ),
                    Icon(Icons.drag_handle, key: i == 0 ? _dragKey : null),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
