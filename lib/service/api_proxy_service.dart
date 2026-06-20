import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_proxy_config.dart';
import 'auth_token_service.dart';

class ApiProxyService {
  ApiProxyService._()
      : _dio = _createDio(),
        _plainDio = Dio();

  static final ApiProxyService instance = ApiProxyService._();

  final Dio _dio;
  final Dio _plainDio;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 20),
        contentType: 'application/json',
      ),
    );
    dio.interceptors.add(_AuthInterceptor());
    return dio;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    return _dio.get<T>(
      ApiProxyConfig.join(path),
      queryParameters: queryParameters,
      options: receiveTimeout != null
          ? Options(receiveTimeout: receiveTimeout)
          : null,
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
      options: (receiveTimeout != null || sendTimeout != null)
          ? Options(receiveTimeout: receiveTimeout, sendTimeout: sendTimeout)
          : null,
    );
  }

  Future<void> download(String url, String savePath) {
    return _plainDio.download(url, savePath);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await AuthTokenService.getIdToken();
      if (token == null || token.isEmpty) {
        debugPrint('[AuthInterceptor] no token for ${options.path}');
        handler.reject(
          DioException(
            requestOptions: options,
            error: StateError('Cognito 登录态不可用，无法访问云端代理。'),
            type: DioExceptionType.cancel,
          ),
        );
        return;
      }
      debugPrint(
        '[AuthInterceptor] ${options.path} token=${token.substring(0, token.length > 10 ? 10 : token.length)}...',
      );
      options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } catch (e) {
      debugPrint('[AuthInterceptor] onRequest error: $e');
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 &&
        err.requestOptions.extra['_authRetry'] != true) {
      debugPrint(
        '[AuthInterceptor] 401 on ${err.requestOptions.path}, retrying with fresh token...',
      );
      final options = err.requestOptions.copyWith(
        extra: {...err.requestOptions.extra, '_authRetry': true},
      );
      try {
        final token = await AuthTokenService.getIdToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
          final dio = Dio();
          final response = await dio.fetch(options);
          handler.resolve(response);
          return;
        }
      } catch (e) {
        debugPrint('[AuthInterceptor] retry failed: $e');
      }
    }
    handler.next(err);
  }
}
