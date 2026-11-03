import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import 'home_dashboard_screen.dart';

/// Màn hình Xác thực (Đăng nhập & Đăng ký Email/Password) với Supabase BaaS
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Controllers cho Đăng nhập
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Controllers cho Đăng ký
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmPasswordController = TextEditingController();

  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureRegisterConfirmPassword = true;
  bool _isLoading = false;

  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    if (!AppConstants.isSupabaseInitialized) {
      _showErrorSnackBar(
        'Supabase chưa được kết nối. Vui lòng bấm "Dùng thử Offline" bên dưới để vào app ngay!',
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final email = _loginEmailController.text.trim();
      final password = _loginPasswordController.text;

      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (res.user != null && mounted) {
        // Tự động kích hoạt đồng bộ khi đăng nhập thành công
        ref.read(syncControllerProvider.notifier).triggerManualSync();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.emeraldAccent,
            content: Text('Đăng nhập thành công! Chào mừng ${res.user!.email}'),
          ),
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        String message = e.message;
        if (e.message.contains('Invalid login credentials')) {
          message = 'Email hoặc mật khẩu không chính xác.';
        } else if (e.message.contains('Email not confirmed')) {
          message = 'Email chưa được xác thực. Vui lòng kiểm tra hộp thư hoặc tắt Confirm Email trong Supabase.';
        }
        _showErrorSnackBar(message);
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Lỗi kết nối: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    if (!AppConstants.isSupabaseInitialized) {
      _showErrorSnackBar(
        'Supabase chưa được kết nối. Vui lòng bấm "Dùng thử Offline" bên dưới để vào app ngay!',
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final email = _registerEmailController.text.trim();
      final password = _registerPasswordController.text;

      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      if (mounted) {
        if (res.session != null) {
          // Confirm email tắt -> đăng nhập vào luôn
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.emeraldAccent,
              content: Text('Đăng ký thành công! Đã đăng nhập với ${res.user!.email}'),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
          );
        } else {
          // Confirm email bật -> cần xác nhận qua email
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.primarySkyBlue,
              duration: Duration(seconds: 5),
              content: Text(
                'Đăng ký thành công! Vui lòng kiểm tra email để xác nhận (hoặc tắt "Confirm email" trong Supabase để vào thẳng).',
              ),
            ),
          );
          _tabController.animateTo(0);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        String message = e.message;
        if (e.message.contains('User already registered')) {
          message = 'Email này đã được đăng ký. Vui lòng chuyển sang tab Đăng nhập.';
        }
        _showErrorSnackBar(message);
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Lỗi đăng ký: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(message),
      ),
    );
  }

  void _enterAsGuest() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Icon & Branding
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppConstants.appName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConstants.universityDepartment,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Tab Bar (Đăng nhập / Đăng ký)
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppTheme.primarySkyBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor:
                          isDark ? Colors.white70 : Colors.black87,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Đăng Nhập'),
                        Tab(text: 'Đăng Ký'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tab Views
                  SizedBox(
                    height: 320,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLoginForm(),
                        _buildRegisterForm(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Nút bỏ qua / chế độ Offline Demo
                  TextButton.icon(
                    onPressed: _isLoading ? null : _enterAsGuest,
                    icon: const Icon(Icons.offline_bolt_outlined, size: 18),
                    label: const Text('Dùng thử Offline (Không cần tài khoản)'),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _loginEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email sinh viên',
              hintText: 'student@vku.udn.vn',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Vui lòng nhập email';
              if (!v.contains('@')) return 'Email không hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _loginPasswordController,
            obscureText: _obscureLoginPassword,
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureLoginPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () {
                  setState(
                      () => _obscureLoginPassword = !_obscureLoginPassword);
                },
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
              if (v.length < 6) return 'Mật khẩu tối thiểu 6 ký tự';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primarySkyBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Đăng Nhập',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _registerEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'name@gmail.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Vui lòng nhập email';
              if (!v.contains('@')) return 'Email không hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registerPasswordController,
            obscureText: _obscureRegisterPassword,
            decoration: InputDecoration(
              labelText: 'Mật khẩu (tối thiểu 6 ký tự)',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegisterPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () {
                  setState(() => _obscureRegisterPassword =
                      !_obscureRegisterPassword);
                },
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
              if (v.length < 6) return 'Mật khẩu tối thiểu 6 ký tự';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _registerConfirmPasswordController,
            obscureText: _obscureRegisterConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Xác nhận mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegisterConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () {
                  setState(() => _obscureRegisterConfirmPassword =
                      !_obscureRegisterConfirmPassword);
                },
              ),
            ),
            validator: (v) {
              if (v != _registerPasswordController.text) {
                return 'Mật khẩu xác nhận không khớp';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleRegister,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primarySkyBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Tạo Tài Khoản',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

