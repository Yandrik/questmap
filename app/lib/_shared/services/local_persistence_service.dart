import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalJsonRecord {
  const LocalJsonRecord({
    required this.namespace,
    required this.id,
    required this.schemaVersion,
    required this.payloadJson,
    required this.updatedAt,
  });

  final String namespace;
  final String id;
  final int schemaVersion;
  final String payloadJson;
  final DateTime updatedAt;
}

abstract interface class LocalPersistenceStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> getKeys();
}

class SharedPreferencesLocalPersistenceStore implements LocalPersistenceStore {
  SharedPreferencesLocalPersistenceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<Set<String>> getKeys() => _preferences.getKeys();

  @override
  Future<void> remove(String key) => _preferences.remove(key);

  @override
  Future<void> setString(String key, String value) {
    return _preferences.setString(key, value);
  }
}

class MemoryLocalPersistenceStore implements LocalPersistenceStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<Set<String>> getKeys() async => _values.keys.toSet();

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}

class LocalPersistenceService {
  LocalPersistenceService([LocalPersistenceStore? store])
    : _store = store ?? SharedPreferencesLocalPersistenceStore();

  static const _keyPrefix = 'localJsonRecords';

  final LocalPersistenceStore _store;

  Future<void> putJson({
    required String namespace,
    required String id,
    required Map<String, Object?> payload,
    int schemaVersion = 1,
  }) async {
    final record = LocalJsonRecord(
      namespace: namespace,
      id: id,
      schemaVersion: schemaVersion,
      payloadJson: jsonEncode(payload),
      updatedAt: DateTime.now().toUtc(),
    );
    await _store.setString(
      _key(namespace, id),
      jsonEncode(_recordToJson(record)),
    );
  }

  Future<Map<String, Object?>?> getJson({
    required String namespace,
    required String id,
  }) async {
    final record = await _getRecord(namespace: namespace, id: id);
    if (record == null) return null;
    final decoded = jsonDecode(record.payloadJson);
    if (decoded is! Map) {
      throw FormatException('Stored payload $namespace/$id is not an object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<List<LocalJsonRecord>> listRecords(String namespace) async {
    final prefix = _namespacePrefix(namespace);
    final keys = await _store.getKeys();
    final records = <LocalJsonRecord>[];
    for (final key in keys.where((key) => key.startsWith(prefix))) {
      final raw = await _store.getString(key);
      if (raw == null) continue;
      records.add(_recordFromJson(jsonDecode(raw) as Map<String, Object?>));
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  Future<void> deleteJson({required String namespace, required String id}) {
    return _store.remove(_key(namespace, id));
  }

  Future<LocalJsonRecord?> _getRecord({
    required String namespace,
    required String id,
  }) async {
    final raw = await _store.getString(_key(namespace, id));
    if (raw == null) return null;
    return _recordFromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  static String _namespacePrefix(String namespace) => '$_keyPrefix:$namespace:';

  static String _key(String namespace, String id) {
    return '${_namespacePrefix(namespace)}$id';
  }

  static Map<String, Object?> _recordToJson(LocalJsonRecord record) {
    return {
      'namespace': record.namespace,
      'id': record.id,
      'schemaVersion': record.schemaVersion,
      'payloadJson': record.payloadJson,
      'updatedAt': record.updatedAt.toIso8601String(),
    };
  }

  static LocalJsonRecord _recordFromJson(Map<String, Object?> json) {
    return LocalJsonRecord(
      namespace: json['namespace'] as String,
      id: json['id'] as String,
      schemaVersion: json['schemaVersion'] as int,
      payloadJson: json['payloadJson'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }
}
