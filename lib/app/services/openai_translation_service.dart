import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:transla_screen/app/services/logger_service.dart';
import 'package:transla_screen/app/core/models/ocr_result.dart';

class OpenAiTranslationService {
  final http.Client _httpClient;
  final String apiKey;
  final String apiEndpoint;
  final String model;

  OpenAiTranslationService({
    required this.apiKey,
    required this.apiEndpoint,
    required this.model,
    http.Client? client,
  }) : _httpClient = client ?? http.Client();

  Future<String> translate(
      String textToTranslate, String targetLanguage) async {
    if (apiKey.isEmpty || apiKey == 'YOUR_OPENAI_API_KEY') {
      // Also check for placeholder
      log.w(
          'OpenAI Translation API Key is not set or is invalid. Please configure it in settings.');
      return 'Error: Translation API Key not configured.';
    }
    if (textToTranslate.isEmpty) {
      return ''; // Nothing to translate
    }

    final String prompt =
        'Translate the following text to $targetLanguage. Return only the translated text, without any additional explanations, introductory phrases, or quotation marks. If the input text is already in $targetLanguage or cannot be meaningfully translated (e.g., it is a random string of characters), try to return the original text or an appropriate indication that no translation was performed. Text to translate: "$textToTranslate"';

    final Map<String, dynamic> requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a helpful translation assistant.'
        },
        {'role': 'user', 'content': prompt}
      ],
      'max_tokens': textToTranslate.length * 2 +
          150, // Estimate based on input length plus some buffer
      'temperature':
          0.3, // Lower temperature for more deterministic translation
    };

    try {
      final response = await _httpClient.post(
        Uri.parse(apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody =
            jsonDecode(utf8.decode(response.bodyBytes));

        // log.d("OpenAI Translation Raw Response: ${response.body}");

        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty &&
            responseBody['choices'][0]['message'] != null &&
            responseBody['choices'][0]['message']['content'] != null) {
          String translatedText =
              responseBody['choices'][0]['message']['content'];
          // Sometimes the model might still wrap the output in quotes, try to remove them.
          if ((translatedText.startsWith('"') &&
                  translatedText.endsWith('"')) ||
              (translatedText.startsWith("'") &&
                  translatedText.endsWith("'"))) {
            translatedText =
                translatedText.substring(1, translatedText.length - 1);
          }
          return translatedText.trim();
        } else {
          log.e(
              'OpenAI Translation response does not contain expected content structure. Response body: ${response.body}');
          return 'Error: Translation response structure error.';
        }
      } else {
        log.e(
            'OpenAI Translation API Error: ${response.statusCode} - ${response.body}');
        return 'Error: Translation API Error ${response.statusCode}. Check logs.';
      }
    } catch (e, s) {
      log.e('Error calling OpenAI Translation API: $e',
          error: e, stackTrace: s);
      return 'Error: Exception during translation. Check logs.';
    }
  }

  /// 结构化翻译，接收OCR结果数组，返回对应的翻译
  Future<Map<String, String>> translateStructured(
      List<OcrResult> ocrResults, String targetLanguage) async {
    if (apiKey.isEmpty || apiKey == 'YOUR_OPENAI_API_KEY') {
      log.w(
          'OpenAI Translation API Key is not set or is invalid. Please configure it in settings.');
      return {'error': 'Translation API Key not configured.'};
    }

    if (ocrResults.isEmpty) {
      return {}; // Nothing to translate
    }

    // 构建JSON结构的输入
    final Map<String, dynamic> inputData = {
      'texts': ocrResults.map((result) => result.text).toList(),
    };

    final String inputJson = jsonEncode(inputData);
    final String prompt = '''
Translate the following text items to $targetLanguage. 
Input is a JSON object with an array of text items.
Return a JSON object where keys are the original texts and values are the translations.
Only return the valid JSON object without any explanations, markdown formatting, or additional text.
Input: $inputJson
''';

    final Map<String, dynamic> requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a helpful translation assistant that returns valid JSON.'
        },
        {'role': 'user', 'content': prompt}
      ],
      'max_tokens': inputJson.length * 2 +
          200, // Estimate based on input length plus buffer
      'temperature':
          0.3, // Lower temperature for more deterministic translation
    };

    try {
      final response = await _httpClient.post(
        Uri.parse(apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody =
            jsonDecode(utf8.decode(response.bodyBytes));

        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty &&
            responseBody['choices'][0]['message'] != null &&
            responseBody['choices'][0]['message']['content'] != null) {
          String content =
              responseBody['choices'][0]['message']['content'].trim();

          // 尝试解析JSON响应
          try {
            // 如果响应内容被反引号包裹，去除它们
            if (content.startsWith('```json') && content.endsWith('```')) {
              content = content.substring(7, content.length - 3).trim();
            } else if (content.startsWith('```') && content.endsWith('```')) {
              content = content.substring(3, content.length - 3).trim();
            }

            Map<String, dynamic> translationsMap = jsonDecode(content);

            // 将动态Map转换为<String, String>格式
            Map<String, String> result = {};
            translationsMap.forEach((key, value) {
              if (value is String) {
                result[key] = value;
              }
            });

            return result;
          } catch (e) {
            log.e(
                'Error parsing translation JSON response: $e. Content: $content');
            return {'error': 'Failed to parse translation response.'};
          }
        } else {
          log.e(
              'OpenAI Translation response does not contain expected content structure. Response body: ${response.body}');
          return {'error': 'Translation response structure error.'};
        }
      } else {
        log.e(
            'OpenAI Translation API Error: ${response.statusCode} - ${response.body}');
        return {
          'error': 'Translation API Error ${response.statusCode}. Check logs.'
        };
      }
    } catch (e, s) {
      log.e('Error calling OpenAI Translation API: $e',
          error: e, stackTrace: s);
      return {'error': 'Exception during translation. Check logs.'};
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
