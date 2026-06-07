import 'package:dio/dio.dart';

import '../model/valhalla_route_request.dart';

class ValhallaClient {
  ValhallaClient({String baseUrl = 'http://localhost:8002', Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final Dio _dio;

  Future<Map<String, dynamic>> status() async {
    final response = await _dio.get<Map<String, dynamic>>('/status');
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> route(ValhallaRouteRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/route',
      data: request.toJson(),
    );
    return response.data ?? <String, dynamic>{};
  }
}
