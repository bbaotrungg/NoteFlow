import 'dart:ui';

/// Khối văn bản kèm tọa độ hình học phục vụ thuật toán Spatial Row Clustering
class SpatialTextElement {
  final String text;
  final Rect boundingBox;
  final double confidence;

  const SpatialTextElement({
    required this.text,
    required this.boundingBox,
    this.confidence = 1.0,
  });

  double get centerY => boundingBox.top + (boundingBox.height / 2.0);
  double get centerX => boundingBox.left + (boundingBox.width / 2.0);
}

/// Dòng văn bản đã được gom cụm không gian (Spatial Row Cluster)
class ClusteredTextRow {
  final int rowIndex;
  final int columnIndex;
  final List<SpatialTextElement> elements;
  final Rect mergedBounds;

  const ClusteredTextRow({
    required this.rowIndex,
    required this.columnIndex,
    required this.elements,
    required this.mergedBounds,
  });

  String get reconstructedLine => elements.map((e) => e.text.trim()).where((s) => s.isNotEmpty).join(' ');
}

/// Kết quả hoàn chỉnh từ pipeline On-Device OCR + Spatial Row Clustering
class OcrExtractionResult {
  final String structuredText;
  final List<ClusteredTextRow> clusteredRows;
  final int detectedColumnsCount;
  final int processingTimeMs;

  const OcrExtractionResult({
    required this.structuredText,
    required this.clusteredRows,
    required this.detectedColumnsCount,
    required this.processingTimeMs,
  });
}
