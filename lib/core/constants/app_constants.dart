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
    defaultValue: 'https://demo-noteflow-vku.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'demo-anon-key-offline-first-mode',
  );

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
