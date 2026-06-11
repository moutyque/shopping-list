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

/// Plays the autonomous demo: drives the real screens via [DemoController]
/// while a spotlight overlay dims the screen, clears a hole over the area
/// being demonstrated, and shows an explainer card narrating each step.
Future<void> runDemo(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = Overlay.of(context, rootOverlay: true);

  final narration = DemoNarration(
    creating: (l.demoStepCreatingTitle, l.demoStepCreatingBody),
    adding: (l.demoStepAddingTitle, l.demoStepAddingBody),
    reordering: (l.demoStepReorderingTitle, l.demoStepReorderingBody),
    shopping: (l.demoStepShoppingTitle, l.demoStepShoppingBody),
    done: (l.demoStepDoneTitle, l.demoStepDoneBody),
  );

  final step = ValueNotifier<DemoStep>(
    DemoStep(narration.creating.$1, narration.creating.$2, DemoFocus.none),
  );
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
    narration: narration,
    onStep: (s) => step.value = s,
  );

  final entry = OverlayEntry(
    builder: (_) => _DemoOverlay(
      step: step,
      skipLabel: l.demoSkip,
      onSkip: controller.abort,
    ),
  );
  overlay.insert(entry);
  try {
    await controller.run();
  } finally {
    entry.remove();
    step.dispose();
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

/// Dimming scrim with an animated spotlight hole + an explainer card. A
/// full-screen absorber under the card swallows taps so the user's touches
/// don't fight the auto-play; the card (with Skip) sits above it and stays live.
class _DemoOverlay extends StatelessWidget {
  final ValueNotifier<DemoStep> step;
  final String skipLabel;
  final VoidCallback onSkip;

  const _DemoOverlay({
    required this.step,
    required this.skipLabel,
    required this.onSkip,
  });

  /// Reserved height at the bottom for the explainer card; the body spotlight
  /// stops short of it so the cutout and the card never overlap.
  static const double _cardReserve = 188;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<DemoStep>(
      valueListenable: step,
      builder: (context, value, _) {
        final hole = _focusRect(media.size, media.padding, value.focus);
        return Stack(
          children: [
            const Positioned.fill(
              child: AbsorbPointer(absorbing: true, child: SizedBox.expand()),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<Rect?>(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  tween: RectTween(end: hole),
                  builder: (context, animated, _) => CustomPaint(
                    painter: _SpotlightPainter(
                      hole: animated,
                      scrim: Colors.black.withValues(alpha: 0.6),
                      border: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                child: _ExplainerCard(
                  step: value,
                  skipLabel: skipLabel,
                  onSkip: onSkip,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Maps a logical [DemoFocus] to a screen rect. Generous, geometry-based
  /// regions (not pixel-exact widgets) so the spotlight is always sensibly
  /// placed regardless of the screen's exact layout.
  Rect? _focusRect(Size size, EdgeInsets padding, DemoFocus focus) {
    switch (focus) {
      case DemoFocus.none:
        return null;
      case DemoFocus.body:
        final top = padding.top + kToolbarHeight + 8;
        final bottom = size.height - _cardReserve - padding.bottom;
        return Rect.fromLTRB(8, top, size.width - 8, bottom);
    }
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final Color scrim;
  final Color border;

  _SpotlightPainter({required this.hole, required this.scrim, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final paint = Paint()..color = scrim;
    if (hole == null) {
      canvas.drawRect(full, paint);
      return;
    }
    final cutout = RRect.fromRectAndRadius(hole!, const Radius.circular(16));
    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRRect(cutout),
    );
    canvas.drawPath(scrimPath, paint);
    canvas.drawRRect(
      cutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = border.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.scrim != scrim || old.border != border;
}

class _ExplainerCard extends StatelessWidget {
  final DemoStep step;
  final String skipLabel;
  final VoidCallback onSkip;

  const _ExplainerCard({
    required this.step,
    required this.skipLabel,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.onInverseSurface, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      step.title,
                      key: ValueKey(step.title),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: scheme.onInverseSurface),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                step.body,
                key: ValueKey(step.body),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onInverseSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onSkip,
                child: Text(skipLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
