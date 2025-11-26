import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../main/main_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? loginType;

  const LoginScreen({
    super.key,
    this.loginType,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill untuk testing (HAPUS DI PRODUCTION)
    // _emailController.text = 'test@example.com';
    // _passwordController.text = 'password123';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _loginTypeTitle {
    if (widget.loginType == null) return 'Login';
    return widget.loginType == 'enumerator'
        ? 'Login Sebagai Mitra'
        : 'Login Sebagai Pegawai BPS';
  }

  String get _loginTypeSubtitle {
    if (widget.loginType == null) return 'Silakan login untuk melanjutkan';
    return widget.loginType == 'enumerator'
        ? 'Enumerator / Petugas Lapangan'
        : 'Supervisor / Administrator';
  }

  IconData get _loginTypeIcon {
    if (widget.loginType == null) return Icons.login;
    return widget.loginType == 'enumerator'
        ? Icons.person_outline
        : Icons.admin_panel_settings_outlined;
  }

  void _showDebugDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      print('❌ Form validation failed');
      return;
    }

    // Get credentials
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    print('\n' + '='*60);
    print('🔐 LOGIN ATTEMPT');
    print('='*60);
    print('📧 Email: $email');
    print('🔑 Password: ${password.replaceAll(RegExp(r'.'), '*')}');
    print('⏰ Time: ${DateTime.now()}');
    print('='*60 + '\n');

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      print('🌐 Calling authProvider.login()...');

      final success = await authProvider.login(email, password);

      print('\n' + '='*60);
      print('📥 LOGIN RESPONSE');
      print('='*60);
      print('✓ Success: $success');
      print('✓ Is Authenticated: ${authProvider.isAuthenticated}');
      print('✓ User: ${authProvider.user?.username ?? "NULL"}');
      print('✓ Token exists: ${authProvider.token != null}');
      print('✓ Error: ${authProvider.error ?? "NONE"}');
      print('='*60 + '\n');

      if (!mounted) {
        print('⚠️ Widget not mounted, aborting navigation');
        return;
      }

      if (success && authProvider.isAuthenticated) {
        print('✅ LOGIN SUCCESS - Navigating to MainScreen');

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Login berhasil!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Wait a moment for snackbar
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        // Navigate and clear all previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const MainScreen(),
          ),
              (route) => false,
        );

        print('✅ Navigation completed');

      } else {
        print('❌ LOGIN FAILED');
        print('Error message: ${authProvider.error}');

        // Show error in dialog for debugging
        _showDebugDialog(
            'Login Failed',
            'Success: $success\n'
                'Authenticated: ${authProvider.isAuthenticated}\n'
                'Error: ${authProvider.error ?? "Unknown error"}\n\n'
                'Check console for detailed logs.'
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    authProvider.error ?? 'Login gagal. Periksa email dan password Anda.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Detail',
              textColor: Colors.white,
              onPressed: () {
                _showDebugDialog(
                  'Error Details',
                  authProvider.error ?? 'No error details available',
                );
              },
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('\n' + '='*60);
      print('💥 EXCEPTION CAUGHT');
      print('='*60);
      print('Error: $e');
      print('StackTrace:');
      print(stackTrace);
      print('='*60 + '\n');

      if (!mounted) return;

      _showDebugDialog(
          'Exception',
          'Error: $e\n\n'
              'StackTrace:\n$stackTrace'
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Error: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0B6BA8)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _loginTypeTitle,
          style: const TextStyle(
            color: Color(0xFF0B6BA8),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Login Type Badge
                if (widget.loginType != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B6BA8).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF0B6BA8).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _loginTypeIcon,
                            size: 20,
                            color: const Color(0xFF0B6BA8),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _loginTypeSubtitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0B6BA8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (widget.loginType != null) const SizedBox(height: 40),

                // Welcome Text
                const Text(
                  'Selamat Datang!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  _loginTypeSubtitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[600],
                  ),
                ),

                const SizedBox(height: 40),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Masukkan email Anda',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF0B6BA8),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email tidak boleh kosong';
                    }
                    // Basic email validation
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Masukkan password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF0B6BA8),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password tidak boleh kosong';
                    }
                    if (value.length < 6) {
                      return 'Password minimal 6 karakter';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hubungi administrator untuk reset password'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Text(
                      'Lupa Password?',
                      style: TextStyle(
                        color: Color(0xFF0B6BA8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Login Button
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B6BA8),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                        : const Text(
                      'LOGIN',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Help Text
                Center(
                  child: Text(
                    'Butuh bantuan? Hubungi administrator',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Debug Info (HAPUS DI PRODUCTION)
                if (true) // Set false di production
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.yellow[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              'DEBUG MODE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Check console untuk log detail.\n'
                              'API Endpoint: https://fieldtrack-15.preview.emergentagent.com/api',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}