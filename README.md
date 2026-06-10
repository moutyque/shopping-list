# Smart Shopping List

A Flutter app that sorts your shopping list into the **order you actually walk the
store**. Add items in any order; the app learns where things are from your past trips and
re-sorts the list into your real pickup order.

The ordering is a **statistical aggregate** of your past runs, not last-write-wins — so a
one-off reordering is a single low-weight data point and the *most recurring* order keeps
winning.

---

## Status

| Area | State |
|------|-------|
| Core learning logic | ✅ done, 18 unit tests |
| Local database + repositories | ✅ done, 5 integration tests (real SQLite) |
| UI (stores, zones, build list, shopping) | ✅ done, 3 widget tests |
| **Total tests** | **26 passing**, analyzer clean |
| Run on Android device | ⏳ toolchain ready — needs phone plugged in |
| Run on iOS | ❌ needs full Xcode (not installed) |
| Phase 2 (shared backend, sync, crowdsourced order) | architected for, not built |

---

## The idea

- You shop at **multiple stores**, each with its own remembered layout.
- A store has **zones** (Produce, Bakery, Dairy…). You set a baseline order by dragging.
- Items come from a growing **catalog** with autocomplete; a reused item remembers its
  usual zone *for that store*.
- While shopping you check items off; the **real pick sequence** is the learning signal.
- The shopping screen sorts the list into the learned walk order and offers a
  **Grouped ⇄ Walk order** toggle.

### How the learning works

1. A completed run produces a sequence of check-offs. Each checked item gets a
   **normalized position** in `(0, 1)` — `(ordinal + 0.5) / total` — so lists of different
   lengths are comparable.
2. Each `(store, item)` keeps the **last ~15 observations**. Its learned position is the
   **median** of that window — robust, so "1 change out of 10" barely moves it.
3. **Zone order is derived**: a zone's position is the mean of its member items' learned
   positions; zones with no history fall back to their seed order. One source of truth.
4. Walk order = zones in derived order, items within a zone by learned position (new items
   go last until they earn history). Grouped and Walk views show the same sequence — the
   toggle only shows/hides zone headers.

---

## Architecture

```
UI (screens/widgets)
  → Controllers (Riverpod providers)
    → Repository INTERFACES        ← Phase-2 swap point
      → Local data source (Drift)  ← v1
  ↘ LearningService (pure Dart, no I/O)   ← the unit-tested core
```

Storage lives behind repository interfaces, so the Phase-2 remote/sync backend plugs in
with no UI changes. All ordering math is in a pure `LearningService` with zero I/O.

**Stack:** Flutter 3.44 · Dart 3.12 · Riverpod (state) · Drift / SQLite (local DB).

### Source layout

```
lib/
  main.dart                         app entry (ProviderScope)
  app/
    app.dart                        MaterialApp + theme
    providers.dart                  DI wiring + reactive providers
  core/learning/
    learning_models.dart            EntryInput, ZoneRank (pure value objects)
    learning_service.dart           normalize / median / mergeObservation /
                                    deriveZoneOrder / orderEntries
  data/
    db/
      app_database.dart             Drift tables + schema
      connection.dart               on-device SQLite connection
    repositories/
      repositories.dart             storage-agnostic interfaces + view models
      drift_repositories.dart       Drift-backed implementations
  features/
    stores/stores_screen.dart       store list + create
    zones/zones_screen.dart         manage zones, drag to set seed order
    list/build_list_screen.dart     catalog autocomplete, qty/note
    list/zone_picker.dart           zone bottom sheet
    shopping/shopping_screen.dart   sorted list, Grouped⇄Walk, check-off, drag, Complete

test/
  core/learning/learning_service_test.dart   18 unit tests
  data/repositories_test.dart                5 integration tests (in-memory SQLite)
  widget_test.dart                           3 widget tests (fake repository)
```

### Data model (Drift tables)

- **Stores** — `id`, `name`
- **Zones** — `id`, `storeId`, `name`, `icon?`, `seedOrder`
- **CatalogItems** — `id`, `name` (unique; global catalog)
- **Placements** — per `(storeId, catalogItemId)`: `zoneId` + `observations` (rolling
  window of normalized positions, serialized)
- **ShoppingLists** ("runs") — `id`, `storeId`, `createdAt`, `status`, `viewMode`
- **ListEntries** — `id`, `listId`, `catalogItemId`, `qty?`, `note?`, `checked`,
  `pickedOrdinal?`, `insertionIndex`

---

## Prerequisites (one-time setup)

### Flutter SDK
Installed via Homebrew:
```bash
brew install --cask flutter      # ~1 GB; needs a few GB free during extraction
```

### Android toolchain
The Android SDK lives at `~/Library/Android/sdk`. cmdline-tools were added and licenses
accepted:
```bash
brew install --cask android-commandlinetools
yes | sdkmanager --sdk_root="$HOME/Library/Android/sdk" --install "cmdline-tools;latest"
yes | flutter doctor --android-licenses
```

Add to `~/.zshrc` so the tools are always on PATH:
```bash
# --- Android SDK (Flutter dev) ---
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
```

Verify: `flutter doctor` should show `[✓] Android toolchain`.

> **iOS:** requires **full Xcode** (App Store, large) plus a signing team — only Command
> Line Tools are installed here, so iOS builds are not possible until Xcode is added.

---

## Deploy to a real Android device (USB)

**On the phone (one-time):**
1. Settings → About phone → tap **Build number** 7× to unlock Developer options.
2. Settings → Developer options → enable **USB debugging**.
3. Plug into the Mac via USB → tap **Allow USB debugging** on the phone.

**On the Mac:**
```bash
cd ~/IdeaProjects/shopping-list
adb devices        # phone should be listed (not "unauthorized")
flutter run        # builds, installs, launches with hot reload attached
```
- `r` = hot reload · `R` = hot restart · `q` = quit
- **First run is slow** — it triggers a Gradle build that downloads dependencies; later
  runs are fast.

**Standalone APK** (keep it on the phone without the cable):
```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Development

```bash
export PATH="$HOME/homebrew/bin:$PATH"   # if Flutter isn't already on PATH

flutter pub get                          # fetch dependencies
dart run build_runner build              # regenerate Drift code (after schema changes)
flutter analyze                          # static analysis
flutter test                             # full test suite (26 tests, ~1s)
flutter test test/core/learning/         # just the learning core
```

### Testing notes
- **Learning core** and **repositories** are tested directly (the latter against in-memory
  SQLite, including the full loop: complete a run → next list sorts into the learned order).
- **Widget tests** drive the UI through a *fake* repository with a controlled stream — never
  a real database. A real Drift stream inside a widget test deadlocks `pumpAndSettle`
  (real-async I/O the fake test clock won't advance). Keep widget tests on fakes; cover DB
  behavior in the repository integration tests.

---

## Manual end-to-end check (on device)

1. Create store "Carrefour" + zones (Produce, Bakery, Dairy, Frozen…); drag to set order.
2. Build a list: autocomplete a few items, add a couple new ones with zones, set a qty/note.
3. Enter shopping mode; confirm it's sorted; flip **Grouped ⇄ Walk order**.
4. Check items off in a deliberate order; tap **Complete run**.
5. Start a new list with the same items in random input order → it now sorts toward the
   previous run's pickup order.
6. Do ~5 runs in order A, then 1 run in a different order → order A still wins (outlier
   resistance).
7. Create a second store → its zones/learning are independent.

---

## Phase 2 (future, not in this build)

Shared backend with accounts + sync and a crowdsourced **default** order per store. The two
layers map onto the same statistical model: a community default = aggregate of everyone's
runs; your personal order = aggregate of *your* runs, overriding the default. Slots in
behind the existing repository interfaces.
