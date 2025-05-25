import 'dart:convert';
import 'dart:typed_data';
import 'dart:math'; // For Point
import 'package:http/http.dart' as http;
import 'package:transla_screen/services/ocr_service.dart'; // For OcrResult
import 'dart:ui' as ui; // For ui.Rect for OcrResult

// IMPORTANT: Replace with your actual OpenAI API Key
const String _openAiApiKey = 'YOUR_OPENAI_API_KEY';
const String _openAiApiEndpoint = 'https://api.openai.com/v1/chat/completions';
// It's better to use the latest vision-supporting model, e.g., gpt-4o or gpt-4-turbo if gpt-4-vision-preview is deprecated
const String _openAiModel = 'gpt-4-vision-preview';

class OpenAiOcrService {
  final http.Client _httpClient;

  OpenAiOcrService({http.Client? client})
      : _httpClient = client ?? http.Client();

  Future<List<OcrResult>> processImageBytes(
      Uint8List pngImageBytes, int imageWidth, int imageHeight) async {
    if (_openAiApiKey == 'YOUR_OPENAI_API_KEY') {
      print(
          'OpenAI API Key is not set. Please configure it in openai_ocr_service.dart');
      // Optionally, throw an exception or return a specific error result
      // For now, returning an empty list to avoid breaking the flow during development
      return [
        OcrResult(
            text: "OpenAI API Key not configured.",
            boundingBox: ui.Rect.zero,
            cornerPoints: [])
      ];
    }

    final String base64Image = base64Encode(pngImageBytes);

    final String prompt =
        "Analyze this image and return all detected text along with their bounding box coordinates in the format: [{ \"text\": \"...\", \"bbox\": [x1, y1, x2, y2] }, ...]. The bounding box coordinates should be absolute pixel values based on the image dimensions (width: $imageWidth, height: $imageHeight). If no text is found, return an empty list [].";

    final Map<String, dynamic> requestBody = {
      'model': _openAiModel,
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
      'max_tokens': 1500, // Adjust as needed, depends on expected text volume
    };

    try {
      final response = await _httpClient.post(
        Uri.parse(_openAiApiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openAiApiKey',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody =
            jsonDecode(utf8.decode(response.bodyBytes));

        // Debug: Print the raw response from OpenAI
        print("OpenAI Raw Response: ${response.body}");

        if (responseBody['choices'] != null &&
            responseBody['choices'].isNotEmpty &&
            responseBody['choices'][0]['message'] != null &&
            responseBody['choices'][0]['message']['content'] != null) {
          String content = responseBody['choices'][0]['message']['content'];

          // The response content might be a JSON string, or a string containing JSON.
          // We need to robustly parse this.
          // First, check if the content *is* the JSON list itself.
          // It might be wrapped in backticks if markdown was used.
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
            final List<dynamic> resultsJson = jsonDecode(content);
            final List<OcrResult> ocrResults = [];
            for (var item in resultsJson) {
              if (item is Map<String, dynamic> &&
                  item['text'] != null &&
                  item['bbox'] != null &&
                  item['bbox'] is List &&
                  item['bbox'].length == 4) {
                final List<dynamic> bboxRaw = item['bbox'];
                // Ensure coordinates are num (int or double) and convert
                final double x1 = (bboxRaw[0] as num).toDouble();
                final double y1 = (bboxRaw[1] as num).toDouble();
                final double x2 = (bboxRaw[2] as num).toDouble();
                final double y2 = (bboxRaw[3] as num).toDouble();

                // Create OcrResult. Note: OpenAI might not provide corner points in the same way ML Kit does.
                // We'll use the bbox to create a Rect and leave cornerPoints empty or derive if necessary.
                // For simplicity, let's assume bbox is [left, top, right, bottom]
                ocrResults.add(OcrResult(
                  text: item['text'] as String,
                  boundingBox: ui.Rect.fromLTRB(x1, y1, x2, y2),
                  cornerPoints: [
                    // Derived from bbox for consistency with OcrResult
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
            print('Problematic content: $content');
            // Return a result indicating parsing failure
            return [
              OcrResult(
                  text: "Error parsing OpenAI response: $e",
                  boundingBox: ui.Rect.zero,
                  cornerPoints: [])
            ];
          }
        } else {
          print('OpenAI response does not contain expected content structure.');
          print('Response body: ${response.body}');
          return [
            OcrResult(
                text:
                    "OpenAI response structure error. Full response: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...",
                boundingBox: ui.Rect.zero,
                cornerPoints: [])
          ];
        }
      } else {
        print('OpenAI API Error: ${response.statusCode} - ${response.body}');
        return [
          OcrResult(
              text:
                  "OpenAI API Error ${response.statusCode}: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...",
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
