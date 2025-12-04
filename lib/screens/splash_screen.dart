import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth/onboarding_screen.dart';
import 'main/main_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../providers/fraud_detection_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // 🆕 Status message untuk menampilkan progress
  String _statusMessage = 'Memuat...';

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );

    _animationController.forward();

    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // Delay untuk animasi splash
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => _statusMessage = 'Memeriksa autentikasi...');

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    if (token != null && token.isNotEmpty) {
      // 🆕 User sudah login sebelumnya (auto-login)
      debugPrint('🔐 SplashScreen: Token ditemukan, auto-login...');
      setState(() => _statusMessage = 'Memulai layanan tracking...');

      // 🆕 CRITICAL: Pre-start services sebelum navigate ke MainScreen
      await _preStartServices();

      // Delay sedikit untuk memastikan services sudah mulai
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    } else if (hasSeenOnboarding) {
      // User sudah lihat onboarding tapi belum login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingScreen(),
        ),
      );
    } else {
      // First time user
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingScreen(),
        ),
      );
      prefs.setBool('has_seen_onboarding', true);
    }
  }

  /// 🆕 NEW: Pre-start services saat auto-login
  /// Ini memastikan tracking sudah aktif sebelum masuk ke MainScreen
  Future<void> _preStartServices() async {
    if (!mounted) return;

    try {
      final authProvider = context.read<AuthProvider>();
      final locationProvider = context.read<LocationProvider>();
      final fraudProvider = context.read<FraudDetectionProvider>();

      // Tunggu AuthProvider selesai load user dari storage
      int retries = 0;
      while (authProvider.user == null && retries < 10) {
        debugPrint('⏳ SplashScreen: Waiting for user data... (${retries + 1}/10)');
        await Future.delayed(const Duration(milliseconds: 200));
        retries++;
      }

      final user = authProvider.user;
      if (user == null) {
        debugPrint('⚠️ SplashScreen: User not loaded after retries, skipping pre-start');
        return;
      }

      debugPrint('🚀 SplashScreen: Pre-starting services for ${user.username}...');

      // Link providers
      authProvider.setProviders(
        locationProvider: locationProvider,
        fraudDetectionProvider: fraudProvider,
      );

      // Start fraud monitoring
      if (!fraudProvider.isMonitoring) {
        // setState(() => _statusMessage = 'Mengaktifkan fraud detection...');
        await fraudProvider.startMonitoring();
        debugPrint('✅ Fraud monitoring pre-started');
      }

      // Start location tracking
      if (!locationProvider.isTracking) {
        setState(() => _statusMessage = 'Mengaktifkan GPS...');
        try {
          await locationProvider.startTrackingWithFraudDetection(user.id);
          debugPrint('✅ Location tracking pre-started');
        } catch (e) {
          debugPrint('⚠️ Pre-start tracking failed: $e (will retry in HomeScreen)');
        }
      }

      setState(() => _statusMessage = 'Siap!');
      debugPrint('✅ SplashScreen: Pre-start completed');

    } catch (e) {
      debugPrint('⚠️ SplashScreen pre-start error: $e');
      // Don't throw - let HomeScreen handle it
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B6BA8),
              Color(0xFF1976D2),
              Color(0xFF2196F3),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo or App Icon
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.rectangle,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(40.0),
                        topRight: Radius.circular(40.0),
                        bottomLeft: Radius.circular(40.0),
                        bottomRight: Radius.circular(40.0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Image.asset(
                        'assets/icons/icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // App Name
                  const Text(
                    'SINTONG',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Tagline
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Field Survey Application',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Loading Indicator
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),

                  // 🆕 Status message
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
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
}