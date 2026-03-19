import 'package:amplify_flutter/amplify_flutter.dart';

class CognitoAuthService {
  const CognitoAuthService();

  Future<bool> isSignedIn() async {
    final session = await Amplify.Auth.fetchAuthSession();
    return session.isSignedIn;
  }

  Future<String?> currentUsername() async {
    final user = await Amplify.Auth.getCurrentUser();
    return user.username;
  }

  Future<void> signOut() async {
    await Amplify.Auth.signOut();
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
}