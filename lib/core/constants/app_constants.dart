import 'package:flutter/foundation.dart';

/// Cấu hình hằng số hệ thống cho NoteFlow AI
class AppConstants {
  AppConstants._();

  static const String appName = 'NoteFlow AI';
  static const String appSubtitle = 'Smart Study Notes & Personalized Revision';
  static const String universityDepartment =
      'Khoa KHMT - ĐH CNTT & TT Việt - Hàn (VKU)';

  // Environment variables via --dart-define
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://teeojjfcmbvzjmtxxucs.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_fK8lwPEIJARBVc0BuPr6NA_U0Q6FoYP',
  );

  /// Tên Supabase Edge Function Proxy cho Gemini AI
  static const String geminiEdgeFunctionName = 'gemini-study-assistant';

  /// Cờ cảnh báo an toàn bản phát hành (Release Safety Guard):
  /// Nếu build Release mà vẫn truyền trực tiếp API Key vào client thay vì qua Edge Function,
  /// đánh dấu bản build là KHÔNG AN TOÀN để phát hành ra công chúng (app stores).
  static const bool isDirectKeyEmbeddedInRelease =
      kReleaseMode && geminiApiKey != '';

  /// Bản phát hành chỉ được xem là an toàn khi không nhúng trực tiếp API Key vào client
  static bool get isSafeForPublicDistribution => !isDirectKeyEmbeddedInRelease;

  /// Thẩm tra tính an toàn của môi trường phát hành (Release Safety Guard).
  /// Ném lỗi StateError nếu ứng dụng chạy ở chế độ Release (kReleaseMode) nhưng vẫn có direct GEMINI_API_KEY nhúng trong binary.
  /// Trong chế độ Debug hoặc Profile (môi trường phát triển cục bộ), hàm này không chặn để hỗ trợ nhà phát triển kiểm thử.
  static void enforceReleaseSafety() {
    if (isDirectKeyEmbeddedInRelease) {
      throw StateError(
        'CRITICAL SECURITY ERROR: Direct Gemini API key detected in a Release build!\n'
        'NoteFlow architecture prohibits embedding GEMINI_API_KEY into distributed release binaries.\n'
        'Please build the release APK with --dart-define=GEMINI_API_KEY="" and route requests through the Supabase Edge Function proxy (gemini-study-assistant).',
      );
    }
  }

  /// Cờ trạng thái Supabase đã được khởi tạo thành công hay chưa
  static bool isSupabaseInitialized = false;

  // Gemini Configuration
  static const String geminiModelName = 'gemini-1.5-flash';
  static const Duration apiTimeout = Duration(seconds: 35);
  static const int maxApiRetries = 3;

  // OCR Spatial Row Clustering Configuration
  static const double rowVerticalOverlapThreshold = 0.55;
  static const double columnGapMultiplier = 2.4;

  // SuperMemo SM-2 Constants
  static const double defaultEaseFactor = 2.5;
  static const double minEaseFactor = 1.3;

  // Sync Engine Constants
  static const int maxSyncRetries = 5;
  static const Duration syncInterval = Duration(minutes: 2);
}
