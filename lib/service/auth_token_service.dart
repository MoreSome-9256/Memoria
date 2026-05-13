/// 认证令牌辅助服务，负责缓存和刷新 API 调用所需的 token。

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthTokenService {
  static String? _cachedAccessToken;
  static DateTime? _tokenExpiryTime;

  static Future<String?> getAccessToken() async {
    try {
      if (_cachedAccessToken != null && _tokenExpiryTime != null) {
        final refreshAt = _tokenExpiryTime!.subtract(const Duration(minutes: 5));
        if (DateTime.now().isBefore(refreshAt)) {
          return _cachedAccessToken;
        }
      }

      final cognitoPlugin = Amplify.Auth.getPlugin(AmplifyAuthCognito.pluginKey);
      final session = await cognitoPlugin.fetchAuthSession();
      if (!session.isSignedIn) {
        return null;
      }

      final accessToken = session.userPoolTokensResult.valueOrNull?.accessToken.raw;
      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      _cachedAccessToken = accessToken;
      _tokenExpiryTime = DateTime.now().add(const Duration(minutes: 55));
      return accessToken;
    } catch (e) {
      debugPrint('AuthTokenService getAccessToken failed: $e');
      return null;
    }
  }

  static void clearCachedToken() {
    _cachedAccessToken = null;
    _tokenExpiryTime = null;
  }
}
