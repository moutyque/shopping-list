import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../l10n/l10n.dart';
import '../list/build_list_screen.dart';
import '../shopping/shopping_screen.dart';
import '../zones/zones_screen.dart';
import 'demo_conductor.dart';
import 'demo_controller.dart';
import 'demo_data.dart';

/// Plays the user-paced guided tour: a [DemoController] drives the real screens
/// while a [DemoConductor] holds the highlight keys and the Next gate, and this
/// overlay dims the screen, rings the widget being demonstrated, and shows the
/// explainer card. The conductor is published on [activeDemoProvider] so the
/// screens wire their widgets to it for the duration.
Future<void> runDemo(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = Overlay.of(context, rootOverlay: true);

  final narration = DemoNarration(
    intro: (l.demoIntroTitle, l.demoIntroBody),
    addAisle: (l.demoAddAisleTitle, l.demoAddAisleBody),
    nameAisle: (l.demoNameAisleTitle, l.demoNameAisleBody),
    confirmAisle: (l.demoConfirmAisleTitle, l.demoConfirmAisleBody),
    restAisles: (l.demoRestAislesTitle, l.demoRestAislesBody),
    typeItem: (l.demoTypeItemTitle, l.demoTypeItemBody),
    tapAdd: (l.demoTapAddTitle, l.demoTapAddBody),
    restItems: (l.demoRestItemsTitle, l.demoRestItemsBody),
    check: (l.demoCheckTitle, l.demoCheckBody),
    complete: (l.demoCompleteTitle, l.demoCompleteBody),
    reveal: (l.demoRevealTitle, l.demoRevealBody),
    done: (l.demoDoneTitle, l.demoDoneBody),
  );

  final conductor = DemoConductor();
  final step = ValueNotifier<DemoStep>(DemoStep(l.demoIntroTitle, l.demoIntroBody));

  final controller = DemoController(
    stores: ref.read(storeRepositoryProvider),
    zones: ref.read(zoneRepositoryProvider),
    catalog: ref.read(catalogRepositoryProvider),
    lists: ref.read(listRepositoryProvider),
    nav: _NavigatorDemoNav(navigator),
    conductor: conductor,
    strings: DemoStrings(
      storeName: l.demoStoreName,
      zones: [l.demoZoneProduce, l.demoZoneBakery, l.demoZoneDairy],
      items: [
        (l.demoItemBananas, l.demoZoneProduce),
        (l.demoItemBread, l.demoZoneBakery),
        (l.demoItemMilk, l.demoZoneDairy),
        (l.demoItemEggs, l.demoZoneDairy),
      ],
    ),
    narration: narration,
    onStep: (s) => step.value = s,
  );

  ref.read(activeDemoProvider.notifier).set(conductor);
  final entry = OverlayEntry(
    builder: (_) => _DemoOverlay(
      conductor: conductor,
      step: step,
      nextLabel: l.demoNext,
      finishLabel: l.demoFinish,
      skipLabel: l.demoSkip,
      zoneConfirmLabel: l.demoAddButton,
    ),
  );
  overlay.insert(entry);
  try {
    await controller.run();
  } finally {
    entry.remove();
    ref.read(activeDemoProvider.notifier).set(null);
    step.dispose();
    conductor.dispose();
  }
}

class _NavigatorDemoNav implements DemoNavigator {
  final NavigatorState nav;
  _NavigatorDemoNav(this.nav);

  @override
  void openZones(Store store) =>
      nav.push(MaterialPageRoute(builder: (_) => ZonesScreen(store: store)));

  @override
  void openBuildList(Store store, ShoppingList list) => nav.push(MaterialPageRoute(
      builder: (_) => BuildListScreen(listId: list.id, store: store)));

  @override
  void openShopping(Store store, ShoppingList list) => nav.push(MaterialPageRoute(
      builder: (_) => ShoppingScreen(listId: list.id, store: store)));

  @override
  void backToStores() => nav.popUntil((r) => r.isFirst);
}

/// Dimming scrim + spotlight hole (below the faux dialog) + a highlight ring
/// (above everything, so it marks targets on the screen and inside the dialog
/// alike) + the explainer card with Next/Finish. A full-screen absorber under
/// it all swallows the user's taps so they don't fight the auto-play.
class _DemoOverlay extends StatefulWidget {
  final DemoConductor conductor;
  final ValueNotifier<DemoStep> step;
  final String nextLabel;
  final String finishLabel;
  final String skipLabel;
  final String zoneConfirmLabel;

  const _DemoOverlay({
    required this.conductor,
    required this.step,
    required this.nextLabel,
    required this.finishLabel,
    required this.skipLabel,
    required this.zoneConfirmLabel,
  });

  @override
  State<_DemoOverlay> createState() => _DemoOverlayState();
}

class _DemoOverlayState extends State<_DemoOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Re-read the live target rect every frame: targets appear after
    // navigation and the faux dialog after a rebuild, so a one-shot read races.
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// The on-screen rect of [key], padded a little, or null when not laid out.
  Rect? _rectFor(GlobalKey? key) {
    if (key == null) return null;
    final ctx = key.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return (topLeft & box.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final conductor = widget.conductor;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [conductor.target, conductor.zoneDialogVisible, conductor.isLast, widget.step]),
      builder: (context, _) {
        final hole = _rectFor(conductor.target.value);
        final dialogVisible = conductor.zoneDialogVisible.value;
        // Move the card out of the way when the highlight is low on screen.
        final cardAtTop = hole != null && hole.center.dy > media.size.height * 0.62;
        return Stack(
          children: [
            const Positioned.fill(
              child: AbsorbPointer(absorbing: true, child: SizedBox.expand()),
            ),
            // Dim + reveal the screen target (sits below the faux dialog).
            Positioned.fill(
              child: IgnorePointer(
                child: hole == null
                    ? CustomPaint(
                        painter: _ScrimPainter(
                            hole: null, scrim: Colors.black.withValues(alpha: 0.6)))
                    : TweenAnimationBuilder<Rect?>(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        tween: RectTween(end: hole),
                        builder: (context, animated, _) => CustomPaint(
                          painter: _ScrimPainter(
                              hole: animated,
                              scrim: Colors.black.withValues(alpha: 0.6)),
                        ),
                      ),
              ),
            ),
            if (dialogVisible)
              _FauxZoneDialog(
                controller: conductor.zoneNameController,
                fieldKey: conductor.zoneNameFieldKey,
                confirmKey: conductor.zoneConfirmKey,
                confirmLabel: widget.zoneConfirmLabel,
              ),
            // Highlight ring on top of everything, so it marks dialog targets
            // (above the scrim) as well as screen targets.
            if (hole != null)
              Positioned.fromRect(
                rect: hole,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.primary, width: 3),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              top: cardAtTop ? 0 : null,
              bottom: cardAtTop ? null : 0,
              child: SafeArea(
                child: _ExplainerCard(
                  step: widget.step.value,
                  actionLabel:
                      conductor.isLast.value ? widget.finishLabel : widget.nextLabel,
                  skipLabel: widget.skipLabel,
                  onNext: conductor.advance,
                  onSkip: conductor.abort,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A new-zone dialog drawn inside the overlay (rather than a real modal route,
/// which the spotlight can't reach reliably). Visually mirrors the app's
/// `promptName` dialog; the name is pre-filled by the conductor.
class _FauxZoneDialog extends StatelessWidget {
  final TextEditingController controller;
  final GlobalKey fieldKey;
  final GlobalKey confirmKey;
  final String confirmLabel;

  const _FauxZoneDialog({
    required this.controller,
    required this.fieldKey,
    required this.confirmKey,
    required this.confirmLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Material(
          borderRadius: BorderRadius.circular(28),
          color: Theme.of(context).colorScheme.surface,
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.newZoneTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  key: fieldKey,
                  controller: controller,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: l.nameHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: confirmKey,
                    onPressed: null,
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  final Color scrim;

  _ScrimPainter({required this.hole, required this.scrim});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final paint = Paint()..color = scrim;
    if (hole == null) {
      canvas.drawRect(full, paint);
      return;
    }
    final cutout = RRect.fromRectAndRadius(hole!, const Radius.circular(12));
    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRRect(cutout),
    );
    canvas.drawPath(scrimPath, paint);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.scrim != scrim;
}

class _ExplainerCard extends StatelessWidget {
  final DemoStep step;
  final String actionLabel;
  final String skipLabel;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _ExplainerCard({
    required this.step,
    required this.actionLabel,
    required this.skipLabel,
    required this.onNext,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: onSkip, child: Text(skipLabel)),
                FilledButton(onPressed: onNext, child: Text(actionLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
