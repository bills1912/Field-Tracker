import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_screen.dart'; // Your existing login screen

class LoginMethodScreen extends StatefulWidget {
  const LoginMethodScreen({super.key});

  @override
  State<LoginMethodScreen> createState() => _LoginMethodScreenState();
}

class _LoginMethodScreenState extends State<LoginMethodScreen> {
  bool _isCheckingPermission = false;

  Future<void> _showPermissionDialog() async {
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Perhatian',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF0B6BA8)),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Fasih akan menyimpan lokasi Anda untuk keperluan fitur analisis monitoring bahkan saat aplikasi sedang ditutup atau tidak digunakan.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFF0B6BA8), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'TUTUP',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0B6BA8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _requestLocationPermission();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF0B6BA8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'SETUJU',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    setState(() => _isCheckingPermission = true);

    try {
      // Request location permission
      final status = await Permission.location.request();

      if (status.isGranted) {
        // If granted, also request background location for Android 10+
        if (await Permission.locationAlways.isDenied) {
          await Permission.locationAlways.request();
        }
      }
    } catch (e) {
      print('Error requesting permission: $e');
    } finally {
      setState(() => _isCheckingPermission = false);
    }
  }

  void _navigateToLogin(String loginType) async {
    // Show permission dialog first
    await _showPermissionDialog();

    // Then navigate to login screen
    if (mounted) {
      // PERBAIKAN: Gunakan push() bukan pushReplacement()
      // Agar user bisa kembali ke halaman ini dengan tombol back
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(loginType: loginType),
        ),
      );
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
        title: const Text(
          'Login',
          style: TextStyle(
            color: Color(0xFF0B6BA8),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF0B6BA8)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Informasi'),
                  content: const Text(
                    'Pilih metode login sesuai dengan peran Anda:\n\n'
                        '• Login Sebagai Mitra: Untuk enumerator/petugas lapangan\n'
                        '• Login Sebagai Pegawai BPS: Untuk supervisor/admin',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/login-method-2.png',
                          height: 500,
                          width: 500,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildFallbackIllustration();
                          },
                        ),

                        const SizedBox(height: 20),

                        // Instruction Text
                        Text(
                          'Silakan pilih metode Login',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Login Method Buttons
              Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: 24 + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  children: [
                    // Login as Mitra (Enumerator)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isCheckingPermission
                            ? null
                            : () => _navigateToLogin('enumerator'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B6BA8),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'LOGIN SEBAGAI MITRA',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Login as Pegawai BPS (Supervisor/Admin)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isCheckingPermission
                            ? null
                            : () => _navigateToLogin('supervisor'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B6BA8),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'LOGIN SEBAGAI PEGAWAI BPS',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Loading Indicator
          if (_isCheckingPermission)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Checking permissions...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackIllustration() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildUserIcon(Colors.blue),
              const SizedBox(width: 40),
              _buildUserIcon(Colors.teal),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B6BA8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment, color: Color(0xFF0B6BA8)),
                SizedBox(width: 8),
                Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserIcon(Color color) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: 40,
        color: color,
      ),
    );
  }
}