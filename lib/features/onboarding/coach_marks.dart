import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../l10n/l10n.dart';
import 'onboarding_service.dart';

// Re-export the enums callers need so screens depend only on this file.
export 'package:tutorial_coach_mark/tutorial_coach_mark.dart'
    show ContentAlign, ShapeLightFocus;

/// One step of a coach-mark tour: a widget to spotlight (via [key]) and the
/// explanatory text to show beside it.
class CoachStep {
  final String id;
  final GlobalKey key;
  final String text;
  final ContentAlign align;
  final ShapeLightFocus shape;

  const CoachStep({
    required this.id,
    required this.key,
    required this.text,
    this.align = ContentAlign.bottom,
    this.shape = ShapeLightFocus.RRect,
  });
}

/// Shows [steps] the first time [seenKey] is encountered, then records it as
/// seen. Steps whose target isn't on screen yet are skipped, so a still-loading
/// list can never block the tour.
Future<void> maybeShowCoachMarks(
  BuildContext context, {
  required OnboardingStore store,
  required String seenKey,
  required List<CoachStep> steps,
}) async {
  if (await store.hasSeen(seenKey)) return;
  if (!context.mounted) return;
  await _show(context, store: store, seenKey: seenKey, steps: steps);
}

/// Shows the tour unconditionally (used by the "replay" help action).
Future<void> showCoachMarks(
  BuildContext context, {
  required OnboardingStore store,
  required String seenKey,
  required List<CoachStep> steps,
}) =>
    _show(context, store: store, seenKey: seenKey, steps: steps);

Future<void> _show(
  BuildContext context, {
  required OnboardingStore store,
  required String seenKey,
  required List<CoachStep> steps,
}) async {
  if (!context.mounted) return;
  final visible = steps.where((s) => s.key.currentContext != null).toList();
  if (visible.isEmpty) {
    // Nothing to point at right now; mark seen so we don't retry forever.
    await store.markSeen(seenKey);
    return;
  }
  TutorialCoachMark(
    targets: [
      for (var i = 0; i < visible.length; i++)
        _target(visible[i], isLast: i == visible.length - 1),
    ],
    // Our cards carry their own (localized) Skip button; hide the package's
    // built-in English one. No pulse, so the highlight sits steadily on the
    // element's real bounds instead of shrinking.
    hideSkip: true,
    pulseEnable: false,
    paddingFocus: 8,
    onFinish: () => store.markSeen(seenKey),
    onSkip: () {
      store.markSeen(seenKey);
      return true;
    },
  ).show(context: context);
}

TargetFocus _target(CoachStep step, {required bool isLast}) {
  return TargetFocus(
    identify: step.id,
    keyTarget: step.key,
    shape: step.shape,
    contents: [
      TargetContent(
        align: step.align,
        builder: (context, controller) =>
            _CoachCard(text: step.text, controller: controller, isLast: isLast),
      ),
    ],
  );
}

class _CoachCard extends StatelessWidget {
  final String text;
  final TutorialCoachMarkController controller;
  final bool isLast;

  const _CoachCard({
    required this.text,
    required this.controller,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isLast)
                TextButton(
                    onPressed: controller.skip,
                    child: Text(context.l10n.coachSkip)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: controller.next,
                child: Text(isLast ? context.l10n.coachGotIt : context.l10n.coachNext),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
