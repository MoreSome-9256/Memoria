import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

import 'amplify_cognito_config.dart';

class AmplifyAuthBootstrapService {
  AmplifyAuthBootstrapService._();

  static Future<bool> ensureConfigured() async {
    try {
      if (Amplify.isConfigured) {
        return true;
      }
      await Amplify.addPlugin(AmplifyAuthCognito());
      await Amplify.configure(AmplifyCognitoConfig.build());
      return true;
    } on FormatException catch (error) {
      debugPrint('Amplify auth skipped: ${error.message}');
      return false;
    } catch (error) {
      debugPrint('Amplify auth configure failed: $error');
      if (error.toString().toLowerCase().contains('already configured')) {
        return true;
      }
      return Amplify.isConfigured;
    }
  }
}
