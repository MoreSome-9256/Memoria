// 认证令牌辅助服务，负责缓存和刷新 API 调用所需的 token。

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthTokenService {
  static String? _cachedAccessToken;
  static String? _cachedIdToken;
  static DateTime? _tokenExpiryTime;

  static Future<String?> getAccessToken() async {
    return _getUserPoolToken(
      useIdToken: false,
      readToken: (tokens) => tokens.accessToken.raw,
    );
  }

  static Future<String?> getIdToken() async {
    return _getUserPoolToken(
      useIdToken: true,
      readToken: (tokens) => tokens.idToken.raw,
    );
  }

  static Future<String?> _getUserPoolToken({
    required bool useIdToken,
    required String Function(CognitoUserPoolTokens tokens) readToken,
  }) async {
    try {
      if (!Amplify.isConfigured) {
        debugPrint('AuthTokenService skipped: Amplify Auth is not configured.');
        return null;
      }

      final cachedToken = useIdToken ? _cachedIdToken : _cachedAccessToken;
      if (cachedToken != null && _tokenExpiryTime != null) {
        final refreshAt = _tokenExpiryTime!.subtract(
          const Duration(minutes: 5),
        );
        if (DateTime.now().isBefore(refreshAt)) {
          return cachedToken;
        }
      }

      final cognitoPlugin = Amplify.Auth.getPlugin(
        AmplifyAuthCognito.pluginKey,
      );
      final session = await cognitoPlugin.fetchAuthSession();
      if (!session.isSignedIn) {
        return null;
      }

      final tokens = session.userPoolTokensResult.valueOrNull;
      if (tokens == null) {
        return null;
      }

      final token = readToken(tokens);
      if (token.isEmpty) {
        return null;
      }

      if (useIdToken) {
        _cachedIdToken = token;
      } else {
        _cachedAccessToken = token;
      }
      _tokenExpiryTime = DateTime.now().add(const Duration(minutes: 55));
      return token;
    } catch (e) {
      debugPrint('AuthTokenService getUserPoolToken failed: $e');
      return null;
    }
  }

  static void clearCachedToken() {
    _cachedAccessToken = null;
    _cachedIdToken = null;
    _tokenExpiryTime = null;
  }
}
