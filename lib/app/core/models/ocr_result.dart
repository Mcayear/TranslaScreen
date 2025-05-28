import 'dart:ui' as ui; // For Rect
import 'dart:math'; // For Point

class OcrResult {
  final String text;
  final ui.Rect boundingBox;
  final List<Point<int>> cornerPoints; // Changed to Point<int>

  OcrResult({
    required this.text,
    required this.boundingBox,
    required this.cornerPoints,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'bbox': [
        boundingBox.left,
        boundingBox.top,
        boundingBox.right,
        boundingBox.bottom
      ],
      'cornerPoints': cornerPoints
          .map((p) => {'x': p.x, 'y': p.y})
          .toList(), // Works for Point<num>
    };
  }

  @override
  String toString() {
    return 'Text: "$text", BBox: $boundingBox, Corners: $cornerPoints';
  }
}
