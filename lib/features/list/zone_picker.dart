import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../stores/stores_screen.dart' show promptName;

/// Bottom sheet to choose the zone an item lives in, with an inline "new zone"
/// option. Returns the chosen zone id, or null if dismissed.
Future<int?> pickZone(BuildContext context, WidgetRef ref, int storeId) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final zones = ref.watch(zonesProvider(storeId));
        return SafeArea(
          child: zones.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(32), child: Text('Error: $e')),
            data: (list) => ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Which zone?')),
                for (final z in list)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(z.name),
                    onTap: () => Navigator.pop(context, z.id),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New zone…'),
                  onTap: () async {
                    final name = await promptName(context, title: 'New zone');
                    if (name == null || name.isEmpty) return;
                    final zone =
                        await ref.read(zoneRepositoryProvider).createZone(storeId: storeId, name: name);
                    if (context.mounted) Navigator.pop(context, zone.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
