import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../domain/entities/ocr_result_entity.dart';

/// Phân hệ 2: On-Device OCR (Google ML Kit) kết hợp Thuật toán Gom dòng không gian (Spatial Row Clustering)
///
/// Giải quyết triệt để nhược điểm của ML Kit khi quét slide bài giảng đa cột hoặc bảng biểu:
/// 1. Tích hợp ImagePicker + ImageCropper (UCropActivity với cấu hình tránh tai thỏ Edge-to-Edge).
/// 2. Trích xuất toàn bộ TextLine kèm tọa độ hình học [boundingBox].
/// 3. Phân tích khoảng trống trục hoành (Horizontal X-Projection Histogram) để phát hiện bố cục đa cột.
/// 4. Gom các phần tử có độ chồng lấp trục tung (Vertical Y-Overlap >= 55%) vào cùng một hàng.
/// 5. Sắp xếp các phần tử trong từng hàng từ trái sang phải (X tăng dần) và tái tạo văn bản chuẩn cấu trúc.
class OcrSpatialClusteringService {
  final ImagePicker _imagePicker;
  final ImageCropper _imageCropper;

  OcrSpatialClusteringService({
    ImagePicker? imagePicker,
    ImageCropper? imageCropper,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _imageCropper = imageCropper ?? ImageCropper();

  /// Bước 1: Chụp ảnh hoặc chọn ảnh từ thư viện và cắt phối cảnh (Perspective Crop)
  /// Đã cấu hình tối ưu thanh công cụ tránh tai thỏ (statusBarColor, toolbarColor, activeControlsWidgetColor)
  Future<File?> pickAndCropDocumentImage({required ImageSource source}) async {
    final XFile? pickedFile = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88, // Nén ảnh thông minh tiết kiệm RAM trước khi đưa vào pipeline
      maxWidth: 2200,
      maxHeight: 2200,
    );

    if (pickedFile == null) return null;

    final CroppedFile? croppedFile = await _imageCropper.cropImage(
      sourcePath: pickedFile.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Căn chỉnh vùng tài liệu bài giảng',
          toolbarColor: const Color(0xFF0F172A),
          toolbarWidgetColor: const Color(0xFFFFFFFF),
          activeControlsWidgetColor: const Color(0xFF0284C7),
          backgroundColor: const Color(0xFF0F172A),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Căn chỉnh tài liệu',
          cancelButtonTitle: 'Hủy',
          doneButtonTitle: 'Hoàn tất',
        ),
      ],
    );

    return croppedFile != null ? File(croppedFile.path) : File(pickedFile.path);
  }

  /// Bước 2: Nhận diện văn bản On-Device với Google ML Kit và áp dụng Spatial Row Clustering
  Future<OcrExtractionResult> extractTextFromFile(File imageFile) async {
    final stopwatch = Stopwatch()..start();
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      final elements = <SpatialTextElement>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final rect = line.boundingBox;
          if (line.text.trim().isNotEmpty && rect.width > 0 && rect.height > 0) {
            elements.add(
              SpatialTextElement(
                text: line.text.trim(),
                boundingBox: rect,
                confidence: line.confidence ?? 0.95,
              ),
            );
          }
        }
      }

      stopwatch.stop();
      return clusterSpatialElements(
        elements: elements,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      throw OcrProcessingFailure(
        'Không thể nhận diện văn bản từ ảnh tài liệu: $e',
        originalError: e,
      );
    } finally {
      await textRecognizer.close();
    }
  }

  /// Thuật toán cốt lõi: Spatial Row Clustering & Multi-Column Detection
  /// Có thể kiểm thử độc lập (Unit Testable) trên mọi tập hợp [SpatialTextElement].
  OcrExtractionResult clusterSpatialElements({
    required List<SpatialTextElement> elements,
    int processingTimeMs = 45,
  }) {
    if (elements.isEmpty) {
      return OcrExtractionResult(
        structuredText: '',
        clusteredRows: const [],
        detectedColumnsCount: 1,
        processingTimeMs: processingTimeMs,
      );
    }

    // 1. Phân tách cột (Multi-column Segmentation) nếu tài liệu chia 2 cột rõ rệt
    final List<List<SpatialTextElement>> columns = _segmentColumns(elements);

    final List<ClusteredTextRow> allClusteredRows = [];
    int globalRowCounter = 0;

    // 2. Trong từng cột, gom các phần tử theo hàng ngang dựa trên độ chồng lấp trục Y (Vertical Overlap)
    for (int colIdx = 0; colIdx < columns.length; colIdx++) {
      final colElements = List<SpatialTextElement>.from(columns[colIdx])
        ..sort((a, b) => a.centerY.compareTo(b.centerY));

      final List<List<SpatialTextElement>> rawRows = [];

      for (final elem in colElements) {
        bool addedToExistingRow = false;

        for (final row in rawRows) {
          if (_belongsToSameHorizontalRow(elem, row)) {
            row.add(elem);
            addedToExistingRow = true;
            break;
          }
        }

        if (!addedToExistingRow) {
          rawRows.add([elem]);
        }
      }

      // 3. Sắp xếp các phần tử trong mỗi hàng theo trục X từ trái sang phải
      for (final rowElems in rawRows) {
        rowElems.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        final mergedRect = _computeMergedBounds(rowElems);
        allClusteredRows.add(
          ClusteredTextRow(
            rowIndex: globalRowCounter++,
            columnIndex: colIdx,
            elements: rowElems,
            mergedBounds: mergedRect,
          ),
        );
      }
    }

    // 4. Tái tạo văn bản có cấu trúc theo đúng thứ tự đọc tự nhiên
    final StringBuffer buffer = StringBuffer();
    int currentColumn = 0;
    for (final row in allClusteredRows) {
      if (row.columnIndex != currentColumn) {
        buffer.writeln();
        currentColumn = row.columnIndex;
      }
      final line = row.reconstructedLine;
      if (line.isNotEmpty) {
        buffer.writeln(line);
      }
    }

    return OcrExtractionResult(
      structuredText: buffer.toString().trim(),
      clusteredRows: allClusteredRows,
      detectedColumnsCount: columns.length,
      processingTimeMs: processingTimeMs,
    );
  }

  /// Kiểm tra một phần tử văn bản có thuộc cùng dòng ngang với cụm hiện tại hay không
  /// dựa trên tỷ lệ giao cắt trục tung (Vertical Overlap Ratio) và độ lệch tâm Y.
  bool _belongsToSameHorizontalRow(
    SpatialTextElement candidate,
    List<SpatialTextElement> currentRow,
  ) {
    final Rect rowBounds = _computeMergedBounds(currentRow);
    final double overlapTop = math.max(candidate.boundingBox.top, rowBounds.top);
    final double overlapBottom = math.min(candidate.boundingBox.bottom, rowBounds.bottom);
    final double overlapHeight = math.max(0.0, overlapBottom - overlapTop);

    final double minHeight = math.min(candidate.boundingBox.height, rowBounds.height);
    if (minHeight <= 0) return false;

    final double verticalOverlapRatio = overlapHeight / minHeight;
    final double centerYDiff = (candidate.centerY - rowBounds.center.dy).abs();

    return verticalOverlapRatio >= AppConstants.rowVerticalOverlapThreshold ||
        centerYDiff <= (minHeight * 0.45);
  }

  /// Phát hiện bố cục tài liệu 2 cột (ví dụ bài báo khoa học IEEE/ACM hoặc slide chia đôi)
  List<List<SpatialTextElement>> _segmentColumns(List<SpatialTextElement> elements) {
    if (elements.length < 4) return [elements];

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    for (final e in elements) {
      if (e.boundingBox.left < minX) minX = e.boundingBox.left;
      if (e.boundingBox.right > maxX) maxX = e.boundingBox.right;
    }

    final double pageWidth = maxX - minX;
    if (pageWidth <= 200) return [elements];

    final double midX = minX + pageWidth / 2.0;
    final double gutterZoneHalfWidth = pageWidth * 0.06;

    // Kiểm tra xem có phần tử nào cắt ngang qua đường phân cách giữa trang không
    int crossingMidCount = 0;
    final leftCol = <SpatialTextElement>[];
    final rightCol = <SpatialTextElement>[];

    for (final e in elements) {
      final crossesMid = e.boundingBox.left < (midX - gutterZoneHalfWidth) &&
          e.boundingBox.right > (midX + gutterZoneHalfWidth);
      if (crossesMid) {
        crossingMidCount++;
      }
      if (e.centerX < midX) {
        leftCol.add(e);
      } else {
        rightCol.add(e);
      }
    }

    // Nếu không có dòng nào cắt ngang trục giữa và cả 2 bên đều có nội dung đáng kể => Tài liệu 2 cột
    if (crossingMidCount == 0 && leftCol.length >= 2 && rightCol.length >= 2) {
      return [leftCol, rightCol];
    }

    return [elements];
  }

  Rect _computeMergedBounds(List<SpatialTextElement> elements) {
    double left = elements.first.boundingBox.left;
    double top = elements.first.boundingBox.top;
    double right = elements.first.boundingBox.right;
    double bottom = elements.first.boundingBox.bottom;

    for (final e in elements.skip(1)) {
      left = math.min(left, e.boundingBox.left);
      top = math.min(top, e.boundingBox.top);
      right = math.max(right, e.boundingBox.right);
      bottom = math.max(bottom, e.boundingBox.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
