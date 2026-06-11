import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's chosen locale. `null` means "follow the device locale".
/// The choice is persisted, so it survives restarts.
class LocaleController extends Notifier<Locale?> {
  static const _key = 'locale';

  @override
  Locale? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final code = (await SharedPreferences.getInstance()).getString(_key);
    if (code != null && code != 'system') state = Locale(code);
  }

  /// Pass null to follow the device locale again.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale?.languageCode ?? 'system');
  }
}

final localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
