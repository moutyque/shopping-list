import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/l10n.dart';

enum ShopView { grouped, walk }

/// Shopping mode: the list is sorted into the learned walk order. Toggle
/// between Grouped (zone headers) and Walk order (flat, numbered). Checking an
/// item records the real pick sequence; completing the run feeds the learning
/// core.
class ShoppingScreen extends ConsumerStatefulWidget {
  final int listId;
  final Store store;
  const ShoppingScreen({super.key, required this.listId, required this.store});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  ShopView _view = ShopView.grouped;

  /// Local drag override for walk-order view (does not change learned data;
  /// the check-off sequence is the learning signal).
  List<int>? _manualOrder;

  List<EntryView> _applyManualOrder(List<EntryView> ordered) {
    final manual = _manualOrder;
    if (manual == null) return ordered;
    final byId = {for (final e in ordered) e.entryId: e};
    final result = <EntryView>[];
    for (final id in manual) {
      final e = byId.remove(id);
      if (e != null) result.add(e);
    }
    result.addAll(ordered.where((e) => byId.containsKey(e.entryId)));
    return result;
  }

  Future<void> _complete() async {
    await ref.read(listRepositoryProvider).completeRun(widget.listId);
    if (!mounted) return;
    /* Capture the messenger before popping so the snackbar isn't shown via a
     * torn-down context. popUntil returns to the stores list whether Shop was
     * opened over the build screen or directly from the store's cart action. */
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.runSaved;
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _applyManualOrder(ref.watch(orderedEntriesProvider(widget.listId)));
    final done = entries.where((e) => e.checked).length;
    // The order reflects learning only once at least one item has trip history.
    final learned = entries.any((e) => e.observations.isNotEmpty);
    final demo = ref.watch(activeDemoProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.store.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<ShopView>(
              segments: [
                ButtonSegment(
                    value: ShopView.grouped,
                    icon: const Icon(Icons.dashboard_outlined),
                    label: Text(context.l10n.groupedView)),
                ButtonSegment(
                    value: ShopView.walk,
                    icon: const Icon(Icons.route_outlined),
                    label: Text(context.l10n.walkOrderView)),
              ],
              selected: {_view},
              onSelectionChanged: (s) {
                setState(() => _view = s.first);
                ref.read(listRepositoryProvider).setViewMode(widget.listId, _view.name);
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        completeKey: demo?.completeKey,
        done: done,
        total: entries.length,
        onComplete: entries.isEmpty ? null : _complete,
      ),
      body: entries.isEmpty
          ? Center(child: Text(context.l10n.noItemsOnList))
          : Column(
              children: [
                if (learned) _LearnedBanner(key: demo?.bannerKey),
                Expanded(
                  child: _view == ShopView.grouped
                      ? _GroupedList(
                          entries: entries,
                          onToggle: _toggle,
                          highlightKeyFor: (id) => demo?.checkboxKey(id),
                        )
                      : _WalkList(
                          entries: entries,
                          onToggle: _toggle,
                          onReorderItem: (oldIndex, newIndex) {
                            final ids = entries.map((e) => e.entryId).toList();
                            final moved = ids.removeAt(oldIndex);
                            ids.insert(newIndex, moved);
                            setState(() => _manualOrder = ids);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _toggle(EntryView e) =>
      ref.read(listRepositoryProvider).setChecked(e.entryId, !e.checked);
}

/// Announces that the list's order came from the learning core (the store has
/// past-trip history), so the user understands the list sorted itself.
class _LearnedBanner extends StatelessWidget {
  const _LearnedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.sortedFromLearning,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  final List<EntryView> entries;
  final void Function(EntryView) onToggle;
  final Key? Function(int entryId)? highlightKeyFor;
  const _GroupedList(
      {required this.entries, required this.onToggle, this.highlightKeyFor});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    int? currentZone;
    for (final e in entries) {
      if (e.zoneId != currentZone) {
        currentZone = e.zoneId;
        children.add(_ZoneHeader(label: e.zoneName, icon: e.zoneIcon));
      }
      children.add(_ItemTile(
        entry: e,
        onToggle: onToggle,
        highlightKey: highlightKeyFor?.call(e.entryId),
      ));
    }
    return ListView(children: children);
  }
}

class _WalkList extends StatelessWidget {
  final List<EntryView> entries;
  final void Function(EntryView) onToggle;
  final void Function(int, int) onReorderItem;
  const _WalkList(
      {required this.entries,
      required this.onToggle,
      required this.onReorderItem});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      itemCount: entries.length,
      onReorderItem: onReorderItem,
      itemBuilder: (context, i) {
        final e = entries[i];
        return _ItemTile(
          key: ValueKey(e.entryId),
          entry: e,
          leadingNumber: i + 1,
          onToggle: onToggle,
          trailing: const Icon(Icons.drag_handle),
        );
      },
    );
  }
}

class _ZoneHeader extends StatelessWidget {
  final String label;
  final String? icon;
  const _ZoneHeader({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        '${icon != null ? '$icon  ' : ''}${label.toUpperCase()}',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final EntryView entry;
  final int? leadingNumber;
  final Widget? trailing;
  final void Function(EntryView) onToggle;

  /// When the demo highlights this row, the key it reads the rect from.
  final Key? highlightKey;

  const _ItemTile({
    super.key,
    required this.entry,
    required this.onToggle,
    this.leadingNumber,
    this.trailing,
    this.highlightKey,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (entry.qty != null) '×${entry.qty}',
      if (entry.note != null) entry.note!,
    ];
    return CheckboxListTile(
      key: highlightKey,
      controlAffinity: ListTileControlAffinity.leading,
      value: entry.checked,
      onChanged: (_) => onToggle(entry),
      secondary: trailing,
      title: Row(
        children: [
          if (leadingNumber != null) ...[
            Text('$leadingNumber',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              entry.itemName,
              style: entry.checked
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
          ),
        ],
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int done;
  final int total;
  final VoidCallback? onComplete;
  final Key? completeKey;
  const _BottomBar(
      {required this.done, required this.total, this.onComplete, this.completeKey});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(context.l10n.pickedCount(done, total))),
            FilledButton.icon(
              key: completeKey,
              onPressed: onComplete,
              icon: const Icon(Icons.check),
              label: Text(context.l10n.completeRun),
            ),
          ],
        ),
      ),
    );
  }
}
