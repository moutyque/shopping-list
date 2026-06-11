import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../l10n/l10n.dart';
import '../stores/stores_screen.dart' show promptName;

/// Manage a store's zones: add, rename, and set the baseline (seed) order by
/// dragging. The learned order refines this over time but the seed order is the
/// cold-start fallback.
class ZonesScreen extends ConsumerWidget {
  final Store store;
  const ZonesScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(zonesProvider(store.id));
    final demo = ref.watch(activeDemoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.zonesTitle(store.name))),
      floatingActionButton: FloatingActionButton.extended(
        key: demo?.newZoneFabKey,
        onPressed: () async {
          final name = await promptName(context, title: context.l10n.newZoneTitle);
          if (name == null || name.isEmpty) return;
          await ref
              .read(zoneRepositoryProvider)
              .createZone(storeId: store.id, name: name);
        },
        icon: const Icon(Icons.add),
        label: Text(context.l10n.zoneFab),
      ),
      body: zones.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(context.l10n.zonesEmpty, textAlign: TextAlign.center),
              ),
            );
          }
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
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await promptName(context,
                            title: context.l10n.renameZoneTitle, initial: zone.name);
                        if (name == null || name.isEmpty) return;
                        await ref
                            .read(zoneRepositoryProvider)
                            .renameZone(zone.id, name);
                      },
                    ),
                    const Icon(Icons.drag_handle),
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
