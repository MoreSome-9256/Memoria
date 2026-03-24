import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/auth_token_service.dart';


class CognitoAuthService {
  const CognitoAuthService();

  Future<bool> isSignedIn() async {
    try {
      final session = await Amplify.Auth
          .fetchAuthSession()
          .timeout(const Duration(seconds: 4));
      return session.isSignedIn;
    } catch (error) {
      debugPrint('⚠️ fetchAuthSession 超时或失败，按未登录处理: $error');
      return false;
    }
  }

  Future<String?> currentUsername() async {
    final user = await Amplify.Auth.getCurrentUser();
    return user.username;
  }

  Future<void> signOut() async {
    await Amplify.Auth.signOut();
    AuthTokenService.clearCachedToken();
  }

  Future<SignInResult> signIn({
    required String username,
    required String password,
  }) async {
    return Amplify.Auth.signIn(username: username, password: password);
  }

  Future<SignUpResult> signUp({
    required String username,
    required String password,
    required String email,
    required String name,
  }) async {
    return Amplify.Auth.signUp(
      username: username,
      password: password,
      options: SignUpOptions(
        userAttributes: {
          AuthUserAttributeKey.email: email,
          AuthUserAttributeKey.name: name,
        },
      ),
    );
  }

  Future<SignUpResult> confirmSignUp({
    required String username,
    required String confirmationCode,
  }) async {
    return Amplify.Auth.confirmSignUp(
      username: username,
      confirmationCode: confirmationCode,
    );
  }

  Future<ResetPasswordResult> resetPassword({
    required String username,
  }) async {
    return Amplify.Auth.resetPassword(username: username);
  }

  Future<void> confirmResetPassword({
    required String username,
    required String confirmationCode,
    required String newPassword,
  }) async {
    await Amplify.Auth.confirmResetPassword(
      username: username,
      newPassword: newPassword,
      confirmationCode: confirmationCode,
    );
  }
}