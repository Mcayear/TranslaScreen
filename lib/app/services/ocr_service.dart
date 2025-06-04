import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:transla_screen/app/core/models/ocr_result.dart';
import 'package:transla_screen/app/services/logger_service.dart';

class LocalOcrService {
  final TextRecognizer _textRecognizer;

  LocalOcrService()
      : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<List<OcrResult>> processImageBytes(Uint8List pngImageBytes) async {
    File? tempFile; // Keep a reference to delete it later
    try {
      // 1. Decode PNG bytes to dart:ui.Image to get dimensions (optional if not needed otherwise)
      //    We could skip this if we directly save pngImageBytes to a file,
      //    but if you need ui.Image for other reasons, keep it.
      //    For ML Kit from file, it will read dimensions itself.
      // final ui.Image uiImage = await decodeImageFromList(pngImageBytes);

      // 2. Save the PNG bytes to a temporary file
      final Directory tempDir = await getTemporaryDirectory();
      final String tempPath =
          '${tempDir.path}/ocr_temp_image_${DateTime.now().millisecondsSinceEpoch}.png';
      tempFile = File(tempPath);
      await tempFile.writeAsBytes(pngImageBytes, flush: true);

      // 3. Create InputImage from the file path
      final InputImage inputImage = InputImage.fromFilePath(tempFile.path);

      // 4. Process the image
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      final List<OcrResult> ocrResults = [];
      for (TextBlock block in recognizedText.blocks) {
        ocrResults.add(OcrResult(
          text: block.text,
          boundingBox: block.boundingBox,
          cornerPoints: block.cornerPoints,
        ));
      }

      // uiImage.dispose(); // Only if you decoded and used ui.Image earlier

      return ocrResults;
    } catch (e, s) {
      log.e("[LocalOcrService] Error processing image with ML Kit: $e",
          error: e, stackTrace: s);
      return [];
    } finally {
      // 5. Clean up the temporary file
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
          // log.d("[LocalOcrService] Temporary OCR image deleted: ${tempFile.path}");
        }
      } catch (e, s) {
        log.w("[LocalOcrService] Error deleting temporary OCR image: $e",
            error: e, stackTrace: s);
      }
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
