import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../l10n/l10n.dart';
import '../list/build_list_screen.dart';
import '../shopping/shopping_screen.dart';
import '../zones/zones_screen.dart';
import 'demo_controller.dart';
import 'demo_data.dart';

/// Plays the autonomous demo: inserts a caption/skip overlay, drives the real
/// screens via [DemoController], and tears everything down at the end.
Future<void> runDemo(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = Overlay.of(context, rootOverlay: true);

  final caption = ValueNotifier<String>(l.demoCaptionCreating);
  final controller = DemoController(
    stores: ref.read(storeRepositoryProvider),
    zones: ref.read(zoneRepositoryProvider),
    catalog: ref.read(catalogRepositoryProvider),
    lists: ref.read(listRepositoryProvider),
    nav: _NavigatorDemoNav(navigator),
    strings: DemoStrings(
      storeName: l.demoStoreName,
      zones: [l.demoZoneProduce, l.demoZoneBakery, l.demoZoneDairy, l.demoZoneFrozen],
      items: [
        (l.demoItemBananas, l.demoZoneProduce),
        (l.demoItemApples, l.demoZoneProduce),
        (l.demoItemBread, l.demoZoneBakery),
        (l.demoItemCroissants, l.demoZoneBakery),
        (l.demoItemMilk, l.demoZoneDairy),
        (l.demoItemEggs, l.demoZoneDairy),
        (l.demoItemPizza, l.demoZoneFrozen),
      ],
    ),
    captions: DemoCaptions(
      creating: l.demoCaptionCreating,
      adding: l.demoCaptionAdding,
      reordering: l.demoCaptionReordering,
      shopping: l.demoCaptionShopping,
      done: l.demoCaptionDone,
    ),
    onCaption: (c) => caption.value = c,
  );

  final entry = OverlayEntry(
    builder: (_) => _DemoOverlay(
      caption: caption,
      skipLabel: l.demoSkip,
      onSkip: controller.abort,
    ),
  );
  overlay.insert(entry);
  try {
    await controller.run();
  } finally {
    entry.remove();
    caption.dispose();
  }
}

class _NavigatorDemoNav implements DemoNavigator {
  final NavigatorState nav;
  _NavigatorDemoNav(this.nav);

  @override
  void openBuildList(Store store, ShoppingList list) => nav.push(MaterialPageRoute(
      builder: (_) => BuildListScreen(listId: list.id, store: store)));

  @override
  void openZones(Store store) =>
      nav.push(MaterialPageRoute(builder: (_) => ZonesScreen(store: store)));

  @override
  void openShopping(Store store, ShoppingList list) => nav.push(MaterialPageRoute(
      builder: (_) => ShoppingScreen(listId: list.id, store: store)));

  @override
  void backToStores() => nav.popUntil((r) => r.isFirst);
}

/// Caption bar + Skip button, with a full-screen absorber so the user's taps
/// don't fight the auto-play. Skip sits above the absorber, so it stays live.
class _DemoOverlay extends StatelessWidget {
  final ValueNotifier<String> caption;
  final String skipLabel;
  final VoidCallback onSkip;

  const _DemoOverlay({
    required this.caption,
    required this.skipLabel,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        const Positioned.fill(
          child: AbsorbPointer(absorbing: true, child: SizedBox.expand()),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Material(
              color: scheme.inverseSurface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: caption,
                        builder: (context, value, _) => Text(
                          value,
                          style: TextStyle(color: scheme.onInverseSurface),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onSkip,
                      child: Text(skipLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
