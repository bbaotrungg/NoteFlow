/// Cấu hình hằng số hệ thống cho NoteFlow AI
class AppConstants {
  AppConstants._();

  static const String appName = 'NoteFlow AI';
  static const String appSubtitle = 'Smart Study Notes & Personalized Revision';
  static const String universityDepartment = 'Khoa KHMT - ĐH CNTT & TT Việt - Hàn (VKU)';

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
