import 'dart:convert';
import 'package:http/http.dart' as http;

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
      print(
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

        print("OpenAI Translation Raw Response: ${response.body}");

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
          print(
              'OpenAI Translation response does not contain expected content structure.');
          print('Response body: ${response.body}');
          return 'Error: Translation response structure error.';
        }
      } else {
        print(
            'OpenAI Translation API Error: ${response.statusCode} - ${response.body}');
        return 'Error: Translation API Error ${response.statusCode}. Check logs.';
      }
    } catch (e) {
      print('Error calling OpenAI Translation API: $e');
      return 'Error: Exception during translation. Check logs.';
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
