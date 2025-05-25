import 'dart:convert';
import 'dart:typed_data';
import 'dart:math'; // For Point
import 'package:http/http.dart' as http;
import 'package:transla_screen/services/ocr_service.dart'; // For OcrResult
import 'dart:ui' as ui; // For ui.Rect for OcrResult

// Default values if not configured - API key MUST be provided.
const String _defaultOpenAiApiEndpoint =
    'https://api.openai.com/v1/chat/completions';
const String _defaultOpenAiModel =
    'gpt-4-vision-preview'; // Or 'gpt-4o', 'gpt-4-turbo'

class OpenAiOcrService {
  final http.Client _httpClient;
  final String apiKey;
  final String apiEndpoint;
  final String model;

  OpenAiOcrService({
    required this.apiKey,
    String? apiEndpoint,
    String? model,
    http.Client? client,
  })  : _httpClient = client ?? http.Client(),
        this.apiEndpoint = apiEndpoint ?? _defaultOpenAiApiEndpoint,
        this.model = model ?? _defaultOpenAiModel;

  Future<List<OcrResult>> processImageBytes(
      Uint8List pngImageBytes, int imageWidth, int imageHeight) async {
    if (apiKey.isEmpty || apiKey == 'YOUR_OPENAI_API_KEY') {
      print('OpenAI API Key is not set or is invalid. Please configure it.');
      return [
        OcrResult(
            text: "OpenAI API Key not configured or invalid.",
            boundingBox: ui.Rect.zero,
            cornerPoints: [])
      ];
    }

    final String base64Image = base64Encode(pngImageBytes);

    final String prompt =
        "Analyze this image and return all detected text along with their bounding box coordinates in the format: [{ \"text\": \"...\", \"bbox\": [x1, y1, x2, y2] }, ...]. The bounding box coordinates should be absolute pixel values based on the image dimensions (width: $imageWidth, height: $imageHeight). If no text is found, return an empty list []. Ensure the output is a valid JSON array.";

    final Map<String, dynamic> requestBody = {
      'model': this.model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$base64Image'}
            }
          ]
        }
      ],
      'max_tokens': 2000, // Increased slightly
      // Add response_format for gpt-4-turbo and later models to enforce JSON output
      // 'response_format': { 'type': 'json_object' }, // Uncomment if model supports it
    };

    // If using a model that supports JSON mode (like gpt-4-1106-preview or gpt-4o when 'json_object' is specified)
    // the prompt needs to explicitly instruct the model to produce JSON.
    // The current prompt already does this, but it's good to be aware.
    // if (this.model.contains("1106") || this.model.contains("gpt-4o")) { // Example check
    //   requestBody['response_format'] = {'type': 'json_object'};
    // }

    try {
      final response = await _httpClient.post(
        Uri.parse(this.apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${this.apiKey}',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody =
            jsonDecode(utf8.decode(response.bodyBytes));

        print("OpenAI Raw Response: ${response.body}");

        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty &&
            responseBody['choices'][0]['message'] != null &&
            responseBody['choices'][0]['message']['content'] != null) {
          String content = responseBody['choices'][0]['message']['content'];

          // Handle potential markdown code block for JSON
          if (content.startsWith("```json")) {
            content = content.substring(7);
            if (content.endsWith("```")) {
              content = content.substring(0, content.length - 3);
            }
          } else if (content.startsWith("```")) {
            content = content.substring(3);
            if (content.endsWith("```")) {
              content = content.substring(0, content.length - 3);
            }
          }
          content = content.trim();

          try {
            // If response_format: {'type': 'json_object'} was used and supported,
            // 'content' should directly be a parsable JSON string.
            final List<dynamic> resultsJson = jsonDecode(content);
            final List<OcrResult> ocrResults = [];
            for (var item in resultsJson) {
              if (item is Map<String, dynamic> &&
                  item['text'] != null &&
                  item['bbox'] != null &&
                  item['bbox'] is List &&
                  item['bbox'].length == 4) {
                final List<dynamic> bboxRaw = item['bbox'];
                final double x1 = (bboxRaw[0] as num).toDouble();
                final double y1 = (bboxRaw[1] as num).toDouble();
                final double x2 = (bboxRaw[2] as num).toDouble();
                final double y2 = (bboxRaw[3] as num).toDouble();

                ocrResults.add(OcrResult(
                  text: item['text'] as String,
                  boundingBox: ui.Rect.fromLTRB(x1, y1, x2, y2),
                  cornerPoints: [
                    Point(x1.toInt(), y1.toInt()),
                    Point(x2.toInt(), y1.toInt()),
                    Point(x2.toInt(), y2.toInt()),
                    Point(x1.toInt(), y2.toInt()),
                  ],
                ));
              }
            }
            return ocrResults;
          } catch (e) {
            print('Error parsing OpenAI OCR results JSON: $e');
            print(
                'Problematic content direct from API: ${responseBody['choices'][0]['message']['content']}');
            print('Processed content for parsing: $content');
            return [
              OcrResult(
                  text:
                      "Error parsing OpenAI response JSON: $e. Check logs for raw content.",
                  boundingBox: ui.Rect.zero,
                  cornerPoints: [])
            ];
          }
        } else {
          print('OpenAI response does not contain expected content structure.');
          print('Response body: ${response.body}');
          return [
            OcrResult(
                text: "OpenAI response structure error. Full response in logs.",
                boundingBox: ui.Rect.zero,
                cornerPoints: [])
          ];
        }
      } else {
        print('OpenAI API Error: ${response.statusCode} - ${response.body}');
        return [
          OcrResult(
              text: "OpenAI API Error ${response.statusCode}. Details in logs.",
              boundingBox: ui.Rect.zero,
              cornerPoints: [])
        ];
      }
    } catch (e) {
      print('Error calling OpenAI API: $e');
      return [
        OcrResult(
            text: "Exception calling OpenAI: $e",
            boundingBox: ui.Rect.zero,
            cornerPoints: [])
      ];
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
