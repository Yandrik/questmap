import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/services/local_database.dart';
import 'package:meander/_shared/services/local_persistence_service.dart';

void main() {
  late LocalDatabase database;
  late LocalPersistenceService service;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    service = LocalPersistenceService(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('stores, updates, lists, and deletes JSON payloads', () async {
    await service.putJson(
      namespace: 'drafts',
      id: 'draft-1',
      payload: {
        'title': 'Saturday',
        'steps': ['shop'],
      },
    );
    await service.putJson(
      namespace: 'drafts',
      id: 'draft-1',
      payload: {
        'title': 'Saturday updated',
        'steps': ['shop', 'eat'],
      },
      schemaVersion: 2,
    );

    final payload = await service.getJson(namespace: 'drafts', id: 'draft-1');
    final records = await service.listRecords('drafts');

    expect(payload!['title'], 'Saturday updated');
    expect(payload['steps'], ['shop', 'eat']);
    expect(records.single.schemaVersion, 2);

    await service.deleteJson(namespace: 'drafts', id: 'draft-1');
    expect(await service.getJson(namespace: 'drafts', id: 'draft-1'), isNull);
  });
}
