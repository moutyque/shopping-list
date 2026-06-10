import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// Opens the on-device SQLite file lazily on a background isolate.
AppDatabase openAppDatabase() {
  return AppDatabase(LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'shopping_list.sqlite'));
    return NativeDatabase.createInBackground(file);
  }));
}
