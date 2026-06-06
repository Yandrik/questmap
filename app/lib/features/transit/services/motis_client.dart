import 'package:dio/dio.dart';

import '../model/motis_plan_request.dart';

class MotisClient {
  MotisClient({String baseUrl = 'http://localhost:8010', Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final Dio _dio;

  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/health');
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> plan(MotisPlanRequest request) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v6/plan',
      queryParameters: request.toQueryParameters(),
    );
    return response.data ?? <String, dynamic>{};
  }
}
