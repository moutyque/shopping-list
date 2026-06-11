import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/l10n.dart';
import '../onboarding/demo_conductor.dart';
import '../shopping/shopping_screen.dart';
import '../zones/zones_screen.dart';
import 'zone_picker.dart';

/// Build a list for a store: type to add items via catalog autocomplete
/// (reused items remember their zone), set optional qty/note, then start
/// shopping.
class BuildListScreen extends ConsumerStatefulWidget {
  final int listId;
  final Store store;
  const BuildListScreen({super.key, required this.listId, required this.store});

  @override
  ConsumerState<BuildListScreen> createState() => _BuildListScreenState();
}

class _BuildListScreenState extends ConsumerState<BuildListScreen> {
  final _controller = TextEditingController();
  String _query = '';
  List<CatalogSuggestion> _suggestions = const [];

  /// Set while a guided demo is running: the demo types into its own
  /// controller, so we bind to it and refresh suggestions on its changes.
  DemoConductor? _demo;
  TextEditingController get _search => _demo?.searchController ?? _controller;

  @override
  void initState() {
    super.initState();
    final demo = ref.read(activeDemoProvider);
    if (demo != null) {
      _demo = demo;
      demo.searchController.addListener(_onDemoSearch);
      // The demo may have pre-filled the field before this screen mounted, so
      // the listener missed it — seed the query so the suggestion tile shows.
      _query = demo.searchController.text;
      if (_query.isNotEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _refreshSuggestions(_query));
      }
    }
  }

  void _onDemoSearch() => _onQueryChanged(_demo!.searchController.text);

  @override
  void dispose() {
    _demo?.searchController.removeListener(_onDemoSearch);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _refreshSuggestions(v);
  }

  Future<void> _refreshSuggestions(String q) async {
    final results = await ref.read(catalogRepositoryProvider).suggest(widget.store.id, q);
    if (mounted) setState(() => _suggestions = results);
  }

  Future<void> _addExisting(CatalogSuggestion s) async {
    var zoneId = s.zoneId;
    zoneId ??= await pickZone(context, ref, widget.store.id);
    if (zoneId == null) return;
    await ref.read(listRepositoryProvider).addEntry(
          listId: widget.listId,
          catalogItemId: s.item.id,
          zoneId: zoneId,
        );
    _clear();
  }

  Future<void> _addNew() async {
    final name = _query.trim();
    if (name.isEmpty) return;
    final zoneId = await pickZone(context, ref, widget.store.id);
    if (zoneId == null) return;
    final item = await ref.read(catalogRepositoryProvider).upsertItem(name);
    await ref.read(listRepositoryProvider).addEntry(
          listId: widget.listId,
          catalogItemId: item.id,
          zoneId: zoneId,
        );
    _clear();
  }

  void _clear() {
    _search.clear();
    setState(() {
      _query = '';
      _suggestions = const [];
    });
  }

  bool get _hasExactMatch =>
      _suggestions.any((s) => s.item.name.toLowerCase() == _query.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(entriesProvider(widget.listId));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.store.name),
        actions: [
          IconButton(
            tooltip: context.l10n.manageZonesTooltip,
            icon: const Icon(Icons.shelves),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ZonesScreen(store: widget.store),
            )),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ShoppingScreen(listId: widget.listId, store: widget.store),
            )),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: Text(context.l10n.shopButton),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: _demo?.searchFieldKey,
              controller: _search,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.l10n.addItemHint,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: _clear),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          if (_query.isNotEmpty) _suggestionList(),
          const Divider(height: 1),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => _entryList(list),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionList() {
    return Flexible(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final (i, s) in _suggestions.indexed)
            ListTile(
              // The demo highlights the first suggestion, whatever it is.
              key: i == 0 ? _demo?.addTileKey : null,
              dense: true,
              leading: const Icon(Icons.add_circle_outline),
              title: Text(s.item.name),
              subtitle: s.zoneId == null
                  ? Text(context.l10n.pickAZone)
                  : Text(context.l10n.usedTimes(s.usageCount)),
              onTap: () => _addExisting(s),
            ),
          if (!_hasExactMatch)
            ListTile(
              key: _suggestions.isEmpty ? _demo?.addTileKey : null,
              dense: true,
              leading: const Icon(Icons.add),
              title: Text(context.l10n.addAsNewItem(_query.trim())),
              onTap: _addNew,
            ),
        ],
      ),
    );
  }

  Widget _entryList(List<EntryView> list) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(context.l10n.startTypingHint, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = list[i];
        return ListTile(
          title: Text(e.qty != null ? '${e.itemName}  ×${e.qty}' : e.itemName),
          subtitle: Text([e.zoneName, if (e.note != null) e.note].join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: context.l10n.quantityLabel,
                onPressed: () => _editDetail(e),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref.read(listRepositoryProvider).removeEntry(e.entryId),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editDetail(EntryView e) async {
    final qtyController = TextEditingController(text: e.qty?.toString() ?? '');
    final noteController = TextEditingController(text: e.note ?? '');
    var zoneId = e.zoneId;
    var zoneName = e.zoneName;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(e.itemName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: context.l10n.quantityLabel),
              ),
              TextField(
                controller: noteController,
                decoration: InputDecoration(labelText: context.l10n.noteLabel),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shelves),
                title: Text(context.l10n.zoneLabel),
                subtitle: Text(zoneName),
                trailing: TextButton(
                  child: Text(context.l10n.changeButton),
                  onPressed: () async {
                    final picked = await pickZone(context, ref, widget.store.id);
                    if (picked == null) return;
                    final zones = await ref
                        .read(zoneRepositoryProvider)
                        .watchZones(widget.store.id)
                        .first;
                    final z = zones.firstWhere((z) => z.id == picked);
                    setLocal(() {
                      zoneId = picked;
                      zoneName = z.name;
                    });
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.save)),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final qty = int.tryParse(qtyController.text.trim());
    final note = noteController.text.trim();
    await ref.read(listRepositoryProvider).updateEntry(
          entryId: e.entryId,
          qty: qty,
          note: note.isEmpty ? null : note,
        );
    if (zoneId != e.zoneId) {
      await ref.read(catalogRepositoryProvider).setItemZone(
            storeId: widget.store.id,
            catalogItemId: e.catalogItemId,
            zoneId: zoneId,
          );
    }
  }
}
