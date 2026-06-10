import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/app_database.dart';
import '../list/build_list_screen.dart';
import '../onboarding/coach_marks.dart';
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
  final _fabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFrame());
  }

  /// On launch, open the default store if there is one; otherwise this is a new
  /// (or store-less) user, so show the welcome coach-marks.
  Future<void> _onFirstFrame() async {
    if (_firstFrameDone) return;
    _firstFrameDone = true;
    final store = await ref.read(storeRepositoryProvider).mostUsedStore();
    if (!mounted) return;
    if (store != null) {
      await _openBuildList(store);
    } else {
      await maybeShowCoachMarks(context,
          store: ref.read(onboardingProvider),
          seenKey: CoachKeys.stores,
          steps: _storeSteps());
    }
  }

  List<CoachStep> _storeSteps() => [
        CoachStep(
          id: 'add-store',
          key: _fabKey,
          text: 'Start here: add a store you shop at — '
              'each store keeps its own aisles and learned order.',
        ),
      ];

  Future<void> _replayTutorial() async {
    final store = ref.read(onboardingProvider);
    await store.resetAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tips will show again as you use each screen.')));
    await showCoachMarks(context,
        store: store, seenKey: CoachKeys.stores, steps: _storeSteps());
  }

  /// Resumes the store's in-progress list, creating one only when there is none
  /// (first visit, or the last run was completed).
  Future<ShoppingList> _resumeOrCreate(Store store) async {
    final repo = ref.read(listRepositoryProvider);
    return await repo.activeList(store.id) ?? await repo.createList(store.id);
  }

  Future<void> _addStore() async {
    final name = await _promptName(context, title: 'New store');
    if (name == null || name.isEmpty) return;
    await ref.read(storeRepositoryProvider).createStore(name);
  }

  Future<void> _renameStore(Store store) async {
    final name =
        await _promptName(context, title: 'Rename store', initial: store.name);
    if (name == null || name.isEmpty) return;
    await ref.read(storeRepositoryProvider).renameStore(store.id, name);
  }

  Future<void> _openBuildList(Store store) async {
    final list = await _resumeOrCreate(store);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BuildListScreen(listId: list.id, store: store),
    ));
  }

  Future<void> _openShopping(Store store) async {
    final list = await _resumeOrCreate(store);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShoppingScreen(listId: list.id, store: store),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final stores = ref.watch(storesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My stores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How it works',
            onPressed: _replayTutorial,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: _fabKey,
        onPressed: _addStore,
        icon: const Icon(Icons.add),
        label: const Text('Store'),
      ),
      body: stores.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const _Empty(
              icon: Icons.storefront_outlined,
              title: 'No stores yet',
              message: 'Add a store to start building location-aware lists.',
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
                subtitle: const Text('Tap to build · cart to shop'),
                onTap: () => _openBuildList(store),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shopping_cart_checkout),
                      tooltip: 'Shop',
                      onPressed: () => _openShopping(store),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename store',
                      onPressed: () => _renameStore(store),
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
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save')),
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
  const _Empty({required this.icon, required this.title, required this.message});

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
          ],
        ),
      ),
    );
  }
}
