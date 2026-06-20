// Starter client for routing Memoria cloud API calls through aws_api_proxy.
//
// This file is intentionally kept outside lib/ so it can be copied in when the
// app migration starts. It assumes amplify_flutter and dio are already present.

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:dio/dio.dart';

class ApiProxyClient {
  ApiProxyClient({
    required String baseUrl,
    Dio? dio,
  }) : _baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
       _dio = dio ?? Dio();

  final String _baseUrl;
  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _dio.get<T>(
      '$_baseUrl${_normalizePath(path)}',
      queryParameters: queryParameters,
      options: Options(headers: await _authHeaders()),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
  }) async {
    return _dio.post<T>(
      '$_baseUrl${_normalizePath(path)}',
      data: data,
      options: Options(headers: await _authHeaders()),
    );
  }

  Future<Map<String, String>> _authHeaders() async {
    final session = await Amplify.Auth.fetchAuthSession();
    if (session is! CognitoAuthSession ||
        !session.isSignedIn ||
        session.userPoolTokensResult.valueOrNull == null) {
      throw StateError('Cognito session is not signed in.');
    }
    final token = session.userPoolTokensResult.value.idToken.raw;
    return <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  String _normalizePath(String path) => path.startsWith('/') ? path : '/$path';
}

