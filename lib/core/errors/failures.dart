/// Phân cấp lỗi chuẩn Clean Architecture cho toàn bộ Domain & Data Layer
sealed class AppFailure implements Exception {
  final String message;
  final String? code;
  final Object? originalError;

  const AppFailure(this.message, {this.code, this.originalError});

  @override
  String toString() => '[$runtimeType] $message ${code != null ? "(Code: $code)" : ""}';
}

class DatabaseFailure extends AppFailure {
  const DatabaseFailure(super.message, {super.code, super.originalError});
}

class OcrProcessingFailure extends AppFailure {
  const OcrProcessingFailure(super.message, {super.code, super.originalError});
}

class GeminiAiFailure extends AppFailure {
  final bool isQuotaExceeded;
  final bool isSchemaViolation;

  const GeminiAiFailure(
    super.message, {
    super.code,
    super.originalError,
    this.isQuotaExceeded = false,
    this.isSchemaViolation = false,
  });
}

class SyncEngineFailure extends AppFailure {
  final int failedRecordsCount;

  const SyncEngineFailure(
    super.message, {
    super.code,
    super.originalError,
    this.failedRecordsCount = 0,
  });
}

class NetworkOfflineFailure extends AppFailure {
  const NetworkOfflineFailure([
    super.message = 'Thiết bị đang ngoại tuyến. Dữ liệu đã được lưu vào hàng đợi đồng bộ cục bộ (Sync Queue).',
  ]);
}
