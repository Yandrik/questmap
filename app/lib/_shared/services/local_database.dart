import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

class LocalJsonRecords extends Table {
  TextColumn get namespace => text()();
  TextColumn get id => text()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {namespace, id};
}

@DriftDatabase(tables: [LocalJsonRecords])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

QueryExecutor openLocalDatabaseConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'meander.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
