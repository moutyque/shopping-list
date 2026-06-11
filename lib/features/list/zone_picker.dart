import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../l10n/l10n.dart';
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
                ListTile(title: Text(context.l10n.whichZone)),
                for (final z in list)
                  ListTile(
                    leading: const Icon(Icons.shelves),
                    title: Text(z.name),
                    onTap: () => Navigator.pop(context, z.id),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(context.l10n.newZoneOption),
                  onTap: () async {
                    final name = await promptName(context, title: context.l10n.newZoneTitle);
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
