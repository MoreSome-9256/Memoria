// Cognito-authenticated client for the Memoria cloud API proxy.

import 'package:dio/dio.dart';

import 'api_proxy_config.dart';
import 'auth_token_service.dart';

class ApiProxyService {
  ApiProxyService._()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 20),
          contentType: 'application/json',
        ),
      );

  static final ApiProxyService instance = ApiProxyService._();

  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    return _dio.get<T>(
      ApiProxyConfig.join(path),
      queryParameters: queryParameters,
      options: await _options(receiveTimeout: receiveTimeout),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    return _dio.post<T>(
      ApiProxyConfig.join(path),
      data: data,
      options: await _options(
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
      ),
    );
  }

  Future<void> download(String url, String savePath) {
    return _dio.download(url, savePath);
  }

  Future<Map<String, String>> authHeaders() async {
    final token = await AuthTokenService.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Cognito 登录态不可用，无法访问云端代理。');
    }
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<Options> _options({
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    final headers = await authHeaders();
    return Options(
      headers: headers,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
    );
  }
}
