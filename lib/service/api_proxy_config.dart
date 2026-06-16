// Central configuration for Cognito-protected cloud API proxy calls.

class ApiProxyConfig {
  ApiProxyConfig._();

  static const String defaultBaseUrl =
      'https://t55ki90eu6.execute-api.ap-northeast-2.amazonaws.com';

  static const String baseUrl = String.fromEnvironment(
    'API_PROXY_BASE_URL',
    defaultValue: defaultBaseUrl,
  );

  static const String authMode = String.fromEnvironment(
    'LLM_AUTH_MODE',
    defaultValue: 'cognito_proxy',
  );

  static bool get isEnabled =>
      authMode == 'cognito_proxy' && baseUrl.trim().isNotEmpty;

  static String join(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }
}
