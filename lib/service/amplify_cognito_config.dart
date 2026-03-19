import 'dart:convert';

/// Build Amplify Auth(Cognito) configuration from dart-defines.
///
/// Required defines:
/// - AWS_REGION
/// - COGNITO_USER_POOL_ID
/// - COGNITO_APP_CLIENT_ID
///
/// Optional defines:
/// - COGNITO_IDENTITY_POOL_ID
class AmplifyCognitoConfig {
  static String build() {
    const region = String.fromEnvironment('AWS_REGION', defaultValue: '');
    const userPoolId = String.fromEnvironment(
      'COGNITO_USER_POOL_ID',
      defaultValue: '',
    );
    const appClientId = String.fromEnvironment(
      'COGNITO_APP_CLIENT_ID',
      defaultValue: '',
    );
    const identityPoolId = String.fromEnvironment(
      'COGNITO_IDENTITY_POOL_ID',
      defaultValue: '',
    );

    if (region.isEmpty || userPoolId.isEmpty || appClientId.isEmpty) {
      throw const FormatException(
        'Missing required cognito defines: AWS_REGION, COGNITO_USER_POOL_ID, COGNITO_APP_CLIENT_ID',
      );
    }

    final pluginConfig = <String, Object?>{
      'UserAgent': 'aws-amplify-cli/0.1.0',
      'Version': '0.1.0',
      'IdentityManager': {
        'Default': {},
      },
      'CognitoUserPool': {
        'Default': {
          'PoolId': userPoolId,
          'AppClientId': appClientId,
          'Region': region,
        },
      },
      'Auth': {
        'Default': {
          'authenticationFlowType': 'USER_SRP_AUTH',
        },
      },
    };

    if (identityPoolId.isNotEmpty) {
      pluginConfig['CredentialsProvider'] = {
        'CognitoIdentity': {
          'Default': {
            'PoolId': identityPoolId,
            'Region': region,
          },
        },
      };
    }

    return jsonEncode({
      'auth': {
        'plugins': {
          'awsCognitoAuthPlugin': pluginConfig,
        },
      },
    });
  }
}