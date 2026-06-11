import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale.dart';
import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../../l10n/l10n.dart';
import '../list/build_list_screen.dart';
import '../onboarding/demo_runner.dart';
import '../onboarding/onboarding_service.dart';
import '../shopping/shopping_screen.dart';

class StoresScreen extends ConsumerStatefulWidget {
  const StoresScreen({super.key});

  @override
  ConsumerState<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends ConsumerState<StoresScreen> {
  /// Run the first-frame logic once per app session, so navigating back to this
  /// list (e.g. via the Back button) doesn't re-trigger it.
  bool _firstFrameDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFrame());
  }

  /// On launch: open the default store if there is one; otherwise this is a new
  /// (store-less) user, so play the autonomous demo once.
  Future<void> _onFirstFrame() async {
    if (_firstFrameDone) return;
    _firstFrameDone = true;
    final store = await ref.read(storeRepositoryProvider).mostUsedStore();
    if (!mounted) return;
    if (store != null) {
      await _openBuildList(store);
      return;
    }
    final onboarding = ref.read(onboardingProvider);
    if (await onboarding.hasSeen(DemoFlag.seen)) return;
    await onboarding.markSeen(DemoFlag.seen);
    if (mounted) await runDemo(context, ref);
  }

  Future<void> _pickLanguage() async {
    final current = ref.read(localeProvider)?.languageCode;
    final l = context.l10n;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.language),
        children: [
          _langOption(context, label: l.languageSystem, code: 'system', current: current ?? 'system'),
          _langOption(context, label: 'English', code: 'en', current: current ?? 'system'),
          _langOption(context, label: 'Français', code: 'fr', current: current ?? 'system'),
          _langOption(context, label: 'Español', code: 'es', current: current ?? 'system'),
        ],
      ),
    );
    if (choice == null) return;
    await ref
        .read(localeProvider.notifier)
        .setLocale(choice == 'system' ? null : Locale(choice));
  }

  Widget _langOption(BuildContext context,
      {required String label, required String code, required String current}) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, code),
      child: Row(
        children: [
          Icon(code == current ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  /// Resumes the store's in-progress list, creating one only when there is none
  /// (first visit, or the last run was completed).
  Future<ShoppingList> _resumeOrCreate(Store store) async {
    final repo = ref.read(listRepositoryProvider);
    return await repo.activeList(store.id) ?? await repo.createList(store.id);
  }

  Future<void> _addStore() async {
    final name = await _promptName(context, title: context.l10n.newStoreTitle);
    if (name == null || name.isEmpty) return;
    await ref.read(storeRepositoryProvider).createStore(name);
  }

  Future<void> _renameStore(Store store) async {
    final name = await _promptName(context,
        title: context.l10n.renameStoreTitle, initial: store.name);
    if (name == null || name.isEmpty) return;
    await ref.read(storeRepositoryProvider).renameStore(store.id, name);
  }

  Future<void> _deleteStore(Store store) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteStoreConfirmTitle(store.name)),
        content: Text(l.deleteStoreConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(storeRepositoryProvider).deleteStore(store.id);
  }

  Future<void> _openBuildList(Store store) async {
    final list = await _resumeOrCreate(store);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BuildListScreen(listId: list.id, store: store),
    ));
  }

  Future<void> _openShopping(Store store) async {
    final list = await _resumeOrCreate(store);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShoppingScreen(listId: list.id, store: store),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final stores = ref.watch(storesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.storesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: l.language,
            onPressed: _pickLanguage,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l.howItWorks,
            onPressed: () => runDemo(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStore,
        icon: const Icon(Icons.add),
        label: Text(l.storeFab),
      ),
      body: stores.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _Empty(
              icon: Icons.storefront_outlined,
              title: l.noStoresTitle,
              message: l.noStoresMessage,
              actionLabel: l.loadDemoStore,
              onAction: () => runDemo(context, ref),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final store = list[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.storefront)),
                title: Text(store.name),
                subtitle: Text(l.storeSubtitle),
                onTap: () => _openBuildList(store),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shopping_cart_checkout),
                      tooltip: l.shopTooltip,
                      onPressed: () => _openShopping(store),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: l.renameStoreTooltip,
                      onPressed: () => _renameStore(store),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l.deleteStoreTooltip,
                      onPressed: () => _deleteStore(store),
                    ),
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

/// Small reusable name-entry dialog used across screens.
Future<String?> _promptName(BuildContext context,
    {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: context.l10n.nameHint),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel)),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(context.l10n.save)),
      ],
    ),
  );
}

Future<String?> promptName(BuildContext context,
        {required String title, String initial = ''}) =>
    _promptName(context, title: title, initial: initial);

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.auto_awesome),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
