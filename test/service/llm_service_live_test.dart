import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _apiKey = String.fromEnvironment(
  'LLM_API_KEY',
  defaultValue: 'ms-ad2cccb3-7ad1-452c-ae58-ce8055932c11',
);
const _baseUrl = String.fromEnvironment(
  'LLM_BASE_URL',
  defaultValue: 'https://api-inference.modelscope.cn/v1',
);
const _apiPath = String.fromEnvironment(
  'LLM_API_PATH',
  defaultValue: '/chat/completions',
);
const _model = String.fromEnvironment(
  'LLM_MODEL',
  defaultValue: 'deepseek-ai/DeepSeek-V3.2',
);

void main() {
  group('LLM live request debug', () {
    test('send real online request and print full response', () async {
      final baseUrl = _baseUrl.endsWith('/')
          ? _baseUrl.substring(0, _baseUrl.length - 1)
          : _baseUrl;
      final apiPath = _apiPath.startsWith('/') ? _apiPath : '/$_apiPath';
      final endpoint = '$baseUrl$apiPath';
      final isChatCompletions = apiPath.contains('/chat/completions');

      const systemText = '你是一个中文摄影故事助手，只能基于输入信息生成，不要编造未提供事实。';
      const userPrompt = '''
请写一篇中文博客短文，主题是「周末在杭州西湖拍照」。
要求：
1. 使用第一人称；
2. 300-500 字；
3. 使用 Markdown，包含一个标题和三个小节；
4. 语气温暖自然，结尾给出一句反思。
''';

      final requestBody = isChatCompletions
          ? <String, dynamic>{
              'model': _model,
              'messages': const [
                {'role': 'system', 'content': systemText},
                {'role': 'user', 'content': userPrompt},
              ],
            }
          : <String, dynamic>{
              'model': _model,
              'input': const [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'input_text', 'text': systemText},
                    {'type': 'input_text', 'text': userPrompt},
                  ],
                },
              ],
            };

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 20),
          contentType: 'application/json',
          headers: {'Authorization': 'Bearer $_apiKey'},
        ),
      );

      print('\n===== LLM REQUEST =====');
      print('endpoint: $endpoint');
      print('model: $_model');
      print('apiPath: $apiPath');
      print(
        'requestBody: ${const JsonEncoder.withIndent('  ').convert(requestBody)}',
      );

      try {
        final response = await dio.post(endpoint, data: requestBody);
        final prettyResponse = const JsonEncoder.withIndent(
          '  ',
        ).convert(response.data);

        print('\n===== LLM RESPONSE =====');
        print('statusCode: ${response.statusCode}');
        print('statusMessage: ${response.statusMessage}');
        print('headers: ${response.headers.map}');
        print('data: $prettyResponse');
        print('========================\n');
      } on DioException catch (e) {
        print('\n===== LLM ERROR =====');
        print('type: ${e.type}');
        print('message: ${e.message}');
        print('request: ${e.requestOptions.method} ${e.requestOptions.uri}');
        print('statusCode: ${e.response?.statusCode}');
        print('responseData: ${e.response?.data}');
        print('=====================\n');
        rethrow;
      }
    }, skip: false);
  });
}
