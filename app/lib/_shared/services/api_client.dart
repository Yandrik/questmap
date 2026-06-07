import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required String baseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 45),
            ),
          );

  final Dio _dio;

  Future<Map<String, Object?>> getJson(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    final response = await _dio.get<Object?>(
      path,
      queryParameters: queryParameters,
    );
    return _asMap(response.data);
  }

  Future<Map<String, Object?>> postJson(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    final response = await _dio.post<Object?>(
      path,
      data: data,
      queryParameters: queryParameters,
    );
    return _asMap(response.data);
  }

  Future<void> postNoContent(String path, {Object? data}) async {
    await _dio.post<Object?>(path, data: data);
  }

  Stream<ServerSentEvent> sse(String path) async* {
    final response = await _dio.get<ResponseBody>(
      path,
      options: Options(
        responseType: ResponseType.stream,
        headers: const {'Accept': 'text/event-stream'},
      ),
    );
    final body = response.data;
    if (body == null) return;

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String? eventType;
    final dataLines = <String>[];
    await for (final line in lines) {
      if (line.isEmpty) {
        final event = ServerSentEvent.fromParts(eventType, dataLines);
        if (event != null) yield event;
        eventType = null;
        dataLines.clear();
        continue;
      }
      if (line.startsWith('event:')) {
        eventType = line.substring('event:'.length).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring('data:'.length).trimLeft());
      }
    }

    final event = ServerSentEvent.fromParts(eventType, dataLines);
    if (event != null) yield event;
  }

  void dispose() {
    _dio.close(force: true);
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value == null) return <String, Object?>{};
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw FormatException('Expected JSON object, got ${value.runtimeType}.');
  }
}

class ServerSentEvent {
  const ServerSentEvent({required this.type, required this.data});

  factory ServerSentEvent.fromJsonLine(String line) {
    return ServerSentEvent(
      type: 'message',
      data: jsonDecode(line) as Map<String, Object?>,
    );
  }

  final String type;
  final Map<String, Object?> data;

  static ServerSentEvent? fromParts(String? type, List<String> dataLines) {
    if (dataLines.isEmpty) return null;
    final dataText = dataLines.join('\n');
    final decoded = jsonDecode(dataText);
    if (decoded is! Map) {
      throw FormatException('Expected SSE data object.');
    }
    return ServerSentEvent(
      type: type ?? 'message',
      data: Map<String, Object?>.from(decoded),
    );
  }
}
