import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthTokenService {
  AuthTokenService._();

  static Future<String?> getIdToken() => _getToken(
    readToken: (tokens) => tokens.idToken.raw,
  );

  static Future<String?> getAccessToken() => _getToken(
    readToken: (tokens) => tokens.accessToken.raw,
  );

  static Future<String?> _getToken({
    required String Function(CognitoUserPoolTokens tokens) readToken,
  }) async {
    try {
      if (!Amplify.isConfigured) {
        debugPrint('AuthTokenService skipped: Amplify Auth is not configured.');
        return null;
      }
      final cognitoPlugin = Amplify.Auth.getPlugin(
        AmplifyAuthCognito.pluginKey,
      );
      final session = await cognitoPlugin.fetchAuthSession();
      if (!session.isSignedIn) return null;
      final tokens = session.userPoolTokensResult.valueOrNull;
      if (tokens == null) return null;
      final token = readToken(tokens);
      return token.isEmpty ? null : token;
    } catch (e) {
      debugPrint('AuthTokenService fetchAuthSession failed: $e');
      return null;
    }
  }
}
