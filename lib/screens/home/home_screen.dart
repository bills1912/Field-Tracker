import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/fraud_detection_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/api_service.dart';
import '../surveys/surveys_list_screen.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _servicesInitialized = false;
  bool _isStartingServices = false; // 🆕 Prevent multiple simultaneous starts

  final List<Widget> _screens = [
    const SurveysListScreen(),
    // const MapScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🆕 CRITICAL: Start services setelah frame selesai
    // Ini akan menangani kasus auto-login (buka app tanpa logout)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndStartServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mendeteksi jika aplikasi dibuka kembali dari background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 App Resumed: Ensuring services are running...");
      _ensureServicesRunning();
    }
  }

  /// 🆕 NEW: Initialize dan start semua services
  /// CRITICAL: Ini dipanggil setiap kali HomeScreen dibuat (termasuk auto-login)
  Future<void> _initializeAndStartServices() async {
    if (!mounted) return;
    if (_isStartingServices) return; // Prevent duplicate calls

    _isStartingServices = true;

    final authProvider = context.read<AuthProvider>();
    final locationProvider = context.read<LocationProvider>();
    final fraudProvider = context.read<FraudDetectionProvider>();
    final user = authProvider.user;

    // Tunggu user siap (mungkin masih loading dari SharedPreferences)
    if (user == null) {
      debugPrint("⏳ HomeScreen: Menunggu user...");
      _isStartingServices = false;

      // 🆕 Retry setelah delay jika user belum ready
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && context.read<AuthProvider>().user != null) {
          _initializeAndStartServices();
        }
      });
      return;
    }

    debugPrint("🚀 HomeScreen: User Ready (${user.username}). Initializing services...");

    // 🆕 Link providers ke AuthProvider
    authProvider.setProviders(
      locationProvider: locationProvider,
      fraudDetectionProvider: fraudProvider,
    );

    // 🆕 Sync device info
    try {
      await ApiService.instance.syncDeviceInfo();
    } catch (e) {
      debugPrint("⚠️ Device sync error: $e");
    }

    // 🆕 CRITICAL: Selalu pastikan services berjalan
    // Ini akan menangani kasus auto-login (app dibuka tanpa logout)
    await _forceStartServices();

    _servicesInitialized = true;
    _isStartingServices = false;
  }

  /// 🆕 NEW: Force start services - dipanggil saat init dan resume
  Future<void> _forceStartServices() async {
    if (!mounted) return;

    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    final locationProvider = context.read<LocationProvider>();
    final fraudProvider = context.read<FraudDetectionProvider>();

    debugPrint("🔍 Force checking services status...");
    debugPrint("   - Location tracking: ${locationProvider.isTracking}");
    debugPrint("   - Fraud monitoring: ${fraudProvider.isMonitoring}");

    // 🔒 FORCE START: Start fraud monitoring
    if (!fraudProvider.isMonitoring) {
      debugPrint("🚀 Force starting fraud monitoring...");
      try {
        await fraudProvider.startMonitoring();
        debugPrint("✅ Fraud monitoring started");
      } catch (e) {
        debugPrint("❌ Failed to start fraud monitoring: $e");
      }
    }

    // 🔒 FORCE START: Start location tracking
    if (!locationProvider.isTracking) {
      debugPrint("🚀 Force starting location tracking...");
      try {
        await locationProvider.startTrackingWithFraudDetection(user.id);
        debugPrint("✅ Tracking service started");
      } catch (e) {
        debugPrint("❌ Failed to start tracking: $e");
        if (mounted) _showTrackingErrorDialog(e.toString());
      }
    }

    // 🆕 Force update lokasi pertama untuk memastikan data terkirim
    if (locationProvider.isTracking) {
      try {
        debugPrint("📍 Force updating initial location...");
        await locationProvider.getCurrentLocationWithFraudCheck(user.id);
        debugPrint("✅ Initial location updated");
      } catch (e) {
        debugPrint("⚠️ Force update failed: $e");
      }
    }

    debugPrint("✅ Force start services completed");
  }

  /// 🆕 NEW: Pastikan services selalu berjalan (dipanggil saat resume)
  Future<void> _ensureServicesRunning() async {
    if (!mounted) return;
    if (_isStartingServices) return;

    final user = context.read<AuthProvider>().user;
    if (user == null) {
      debugPrint("⚠️ _ensureServicesRunning: No user, skipping...");
      return;
    }

    // Re-use force start logic
    await _forceStartServices();
  }

  void _showTrackingErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("Tracking Gagal")),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Error: $error"),
            const SizedBox(height: 12),
            const Text(
              "Pastikan GPS aktif dan izin lokasi diberikan.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            // 🆕 Info bahwa tracking wajib
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Tracking lokasi wajib aktif untuk menggunakan aplikasi.",
                      style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text("Pengaturan"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _ensureServicesRunning();
            },
            child: const Text("Coba Lagi"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // 🆕 CRITICAL: Trigger services saat user tersedia (untuk auto-login)
        // Ini menangani kasus ketika user sudah login sebelumnya
        if (authProvider.user != null && !_servicesInitialized && !_isStartingServices) {
          debugPrint("📱 Consumer detected user - triggering service init...");
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeAndStartServices();
          });
        }

        return Scaffold(
          body: Column(
            children: [
              // === STATUS BAR ===
              _buildStatusBar(),

              // === CONTENT ===
              Expanded(
                child: _screens[_currentIndex],
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF2196F3),
            unselectedItemColor: const Color(0xFF666666),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.poll), label: 'Surveys'),
              BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    return Consumer3<NetworkProvider, LocationProvider, FraudDetectionProvider>(
      builder: (context, networkProvider, locationProvider, fraudProvider, _) {
        // 🆕 UPDATED: Status berdasarkan tracking DAN fraud detection
        final isFullyProtected = locationProvider.isTracking && fraudProvider.isMonitoring;

        Color statusColor;
        String statusText;

        if (!locationProvider.isTracking && !fraudProvider.isMonitoring) {
          statusColor = const Color(0xFFF44336); // Merah (Tidak aktif)
          statusText = 'Protection OFF';
        } else if (!isFullyProtected) {
          statusColor = const Color(0xFFFF9800); // Oranye (Partial)
          statusText = 'Partial Protection';
        } else if (!networkProvider.isConnected) {
          statusColor = const Color(0xFFFF9800); // Oranye (Offline)
          statusText = 'Protected (Offline)';
        } else {
          statusColor = const Color(0xFF4CAF50); // Hijau (Aman)
          statusText = 'Fully Protected';
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          color: statusColor,
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Network Status
                Row(
                  children: [
                    Icon(
                      networkProvider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      networkProvider.isConnected ? 'Online' : 'Offline',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                // 🆕 Protection Status (menggantikan Tracking Status)
                Row(
                  children: [
                    Icon(
                      isFullyProtected ? Icons.security : Icons.security_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    // 🆕 Tombol FIX jika tidak fully protected
                    if (!isFullyProtected)
                      GestureDetector(
                        onTap: _ensureServicesRunning,
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "FIX",
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
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
      },
    );
  }
}