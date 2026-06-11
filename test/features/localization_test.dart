import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_list/l10n/l10n.dart';

/// Pumps a trivial widget under a given locale and returns the resolved string.
Future<String> _resolve(
    WidgetTester tester, Locale locale, String Function(AppLocalizations) pick) async {
  late String value;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      value = pick(context.l10n);
      return const SizedBox();
    }),
  ));
  return value;
}

void main() {
  testWidgets('English / French / Spanish resolve from the ARB files',
      (tester) async {
    expect(await _resolve(tester, const Locale('en'), (l) => l.storesTitle),
        'My stores');
    expect(await _resolve(tester, const Locale('fr'), (l) => l.storesTitle),
        'Mes magasins');
    expect(await _resolve(tester, const Locale('es'), (l) => l.storesTitle),
        'Mis tiendas');
  });

  testWidgets('placeholders format per locale', (tester) async {
    expect(await _resolve(tester, const Locale('en'), (l) => l.pickedCount(1, 3)),
        '1 of 3 picked');
    expect(await _resolve(tester, const Locale('fr'), (l) => l.pickedCount(1, 3)),
        '1 sur 3 pris');
  });
}
