import 'dart:typed_data';
import 'dart:ui'
    as ui; // For Rect, Size, Offset, Image, decodeImageFromList, ImageByteFormat
import 'dart:math'; // For Point

import 'package:flutter/painting.dart'; // For decodeImageFromList (might be covered by ui import actually)
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:transla_screen/app/core/models/ocr_result.dart'; // Updated import
import 'package:transla_screen/app/services/logger_service.dart'; // Added logger import

class LocalOcrService {
  final TextRecognizer _textRecognizer;

  // Initialize with specific scripts if needed, e.g., TextRecognizer(script: TextRecognitionScript.chinese)
  // For multiple languages including Latin, Japanese, Chinese, Korean, Devanagari,
  // it might be better to use a recognizer for each script or rely on a general model if available.
  // The plugin docs state: "By default, this package only supports recognition of Latin characters."
  // "If you need to recognize other languages, you need to manually add dependencies [in build.gradle/Podfile]"
  // We have added these dependencies. Let's try with default (Latin) and see if it picks up others.
  // If not, we might need to create separate recognizers like:
  // final _latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  // final _chineseRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  // And then decide which one to use, or run multiple.
  // For simplicity, start with one, assuming the native layer might be smart or default to Latin.
  LocalOcrService()
      : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<List<OcrResult>> processImageBytes(Uint8List pngImageBytes) async {
    try {
      // 1. Decode PNG bytes to dart:ui.Image to get raw pixel data and dimensions
      final ui.Image uiImage = await decodeImageFromList(pngImageBytes);
      final int width = uiImage.width;
      final int height = uiImage.height;

      // 2. Get raw RGBA bytes from ui.Image
      // ML Kit on Android often expects BGRA for InputImageFormat.bgra8888
      // ui.Image.toByteData(format: ui.ImageByteFormat.rawRgba) gives RGBA
      // Let's try with rawRgba and InputImageFormat.rgba8888 first, if available.
      // If not, BGRA might be needed, requiring byte manipulation or checking if MLKit common has rgba8888.
      // According to google_mlkit_commons, InputImageFormat.rgba8888 *is* available.
      final ByteData? byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        log.e(
            "[LocalOcrService] Error: Could not convert ui.Image to ByteData.");
        return [];
      }
      final Uint8List imagePlaneBytes = byteData.buffer.asUint8List();

      final inputImage = InputImage.fromBytes(
        bytes: imagePlaneBytes,
        metadata: InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg, // Assuming upright
          format: InputImageFormat.bgra8888, // Changed to bgra8888
          bytesPerRow:
              width * 4, // For BGRA8888 or RGBA8888, it's width * 4 bytes
        ),
      );

      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);
      final List<OcrResult> ocrResults = [];

      for (TextBlock block in recognizedText.blocks) {
        ocrResults.add(OcrResult(
          text: block.text,
          boundingBox: block.boundingBox,
          cornerPoints:
              block.cornerPoints, // This is List<Point<int>> as per linter
        ));
      }
      // Release the ui.Image
      uiImage.dispose();
      return ocrResults;
    } catch (e, s) {
      log.e("[LocalOcrService] Error processing image with ML Kit: $e",
          error: e, stackTrace: s);
      return [];
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
