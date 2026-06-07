import 'dart:convert';

import 'package:drift/drift.dart';

import 'local_database.dart';

class LocalPersistenceService {
  const LocalPersistenceService(this._database);

  final LocalDatabase _database;

  Future<void> putJson({
    required String namespace,
    required String id,
    required Map<String, Object?> payload,
    int schemaVersion = 1,
  }) async {
    await _database
        .into(_database.localJsonRecords)
        .insertOnConflictUpdate(
          LocalJsonRecordsCompanion.insert(
            namespace: namespace,
            id: id,
            schemaVersion: Value(schemaVersion),
            payloadJson: jsonEncode(payload),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<Map<String, Object?>?> getJson({
    required String namespace,
    required String id,
  }) async {
    final record =
        await (_database.select(_database.localJsonRecords)..where(
              (row) => row.namespace.equals(namespace) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (record == null) return null;
    final decoded = jsonDecode(record.payloadJson);
    if (decoded is! Map) {
      throw FormatException('Stored payload $namespace/$id is not an object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<List<LocalJsonRecord>> listRecords(String namespace) {
    return (_database.select(_database.localJsonRecords)
          ..where((row) => row.namespace.equals(namespace))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Future<void> deleteJson({required String namespace, required String id}) {
    return (_database.delete(_database.localJsonRecords)
          ..where((row) => row.namespace.equals(namespace) & row.id.equals(id)))
        .go();
  }
}
