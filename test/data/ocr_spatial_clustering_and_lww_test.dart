import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteflow_ai/data/services/ocr_spatial_clustering_service.dart';
import 'package:noteflow_ai/domain/entities/ocr_result_entity.dart';

void main() {
  final ocrService = OcrSpatialClusteringService();

  group('On-Device OCR Spatial Row Clustering Tests', () {
    test('Correctly merges words on the same horizontal row and sorts left-to-right', () {
      final scrambledElements = [
        const SpatialTextElement(
          text: 'Architecture',
          boundingBox: Rect.fromLTWH(140, 52, 110, 24),
        ),
        const SpatialTextElement(
          text: 'Clean',
          boundingBox: Rect.fromLTWH(40, 50, 90, 24),
        ),
        const SpatialTextElement(
          text: 'SuperMemo SM-2',
          boundingBox: Rect.fromLTWH(40, 110, 160, 24),
        ),
      ];

      final result = ocrService.clusterSpatialElements(elements: scrambledElements);

      expect(result.clusteredRows.length, 2);
      expect(result.clusteredRows.first.reconstructedLine, 'Clean Architecture');
      expect(result.clusteredRows.last.reconstructedLine, 'SuperMemo SM-2');
    });

    test('Detects 2-column academic layout and reads left column before right column', () {
      final twoColumnElements = [
        // Left column
        const SpatialTextElement(
          text: 'Cot Trai Dong 1',
          boundingBox: Rect.fromLTWH(20, 40, 150, 24),
        ),
        const SpatialTextElement(
          text: 'Cot Trai Dong 2',
          boundingBox: Rect.fromLTWH(20, 80, 150, 24),
        ),
        // Right column
        const SpatialTextElement(
          text: 'Cot Phai Dong 1',
          boundingBox: Rect.fromLTWH(320, 42, 150, 24),
        ),
        const SpatialTextElement(
          text: 'Cot Phai Dong 2',
          boundingBox: Rect.fromLTWH(320, 82, 150, 24),
        ),
      ];

      final result = ocrService.clusterSpatialElements(elements: twoColumnElements);

      expect(result.detectedColumnsCount, 2);
      expect(result.clusteredRows.length, 4);
      expect(result.clusteredRows[0].reconstructedLine, 'Cot Trai Dong 1');
      expect(result.clusteredRows[1].reconstructedLine, 'Cot Trai Dong 2');
      expect(result.clusteredRows[2].reconstructedLine, 'Cot Phai Dong 1');
      expect(result.clusteredRows[3].reconstructedLine, 'Cot Phai Dong 2');
    });
  });
}
