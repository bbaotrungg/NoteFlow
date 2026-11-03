import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/home_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Supabase BaaS an toàn nếu đã cấu hình URL thực tế qua --dart-define
  if (AppConstants.supabaseUrl.isNotEmpty &&
      !AppConstants.supabaseUrl.contains('demo-noteflow-vku')) {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase initialization skipped (Offline-First fallback active): $e');
    }
  }

  runApp(
    const ProviderScope(
      child: NoteFlowAiApp(),
    ),
  );
}

class NoteFlowAiApp extends ConsumerWidget {
  const NoteFlowAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    bool hasSession = false;
    try {
      hasSession = Supabase.instance.client.auth.currentSession != null;
    } catch (_) {}

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: hasSession ? const HomeDashboardScreen() : const AuthScreen(),
    );
  }
}
