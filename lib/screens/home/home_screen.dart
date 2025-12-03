import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/fraud_detection_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/api_service.dart'; // 🆕 Penting untuk syncDeviceInfo
import '../surveys/surveys_list_screen.dart';
// import '../map/map_screen.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _servicesStarted = false; // Flag agar tidak start berulang-ulang

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

    // Coba jalankan service setelah tampilan selesai dirender
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptStartServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mendeteksi jika aplikasi dibuka kembali dari background (Resume)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 App Resumed: Syncing device info & checking services...");
      _attemptStartServices();
    }
  }

  /// Fungsi Utama untuk Menyalakan Semua Service
  Future<void> _attemptStartServices() async {
    if (!mounted) return;

    final user = context.read<AuthProvider>().user;

    // 1. Jika user belum siap (masih loading dari storage), kita tunggu.
    if (user == null) {
      debugPrint("⏳ HomeScreen: Menunggu data user dimuat...");
      return;
    }

    // 2. 🔥 FIX PERANGKAT: Selalu sync device info saat Home dimuat/resume
    // Ini memperbaiki bug dimana ganti device tidak terdeteksi di Dashboard
    try {
      await ApiService.instance.syncDeviceInfo();
    } catch (e) {
      debugPrint("⚠️ Device sync error in Home: $e");
    }

    // Cek Provider
    final locationProvider = context.read<LocationProvider>();
    final fraudProvider = context.read<FraudDetectionProvider>();

    // Jika service sudah jalan semua, kita skip (kecuali Device Sync yg harus selalu jalan)
    if (_servicesStarted && locationProvider.isTracking && fraudProvider.isMonitoring) {
      return;
    }

    debugPrint("🚀 HomeScreen: User Ready (${user.username}). Memulai Services...");
    _servicesStarted = true;

    // 3. Cek & Start Fraud Monitoring (Sensor)
    if (!fraudProvider.isMonitoring) {
      await fraudProvider.startMonitoring();
    }

    // 4. Cek & Start Location Tracking
    if (!locationProvider.isTracking) {
      try {
        await locationProvider.startTrackingWithFraudDetection(user.id);
        debugPrint("✅ Tracking service started");
      } catch (e) {
        debugPrint("❌ Failed to start tracking: $e");
        if (mounted) _showTrackingErrorDialog(e.toString());
      }
    }

    // 5. 🔥 FORCE UPDATE: Paksa kirim lokasi sekarang juga agar Dashboard Online!
    try {
      debugPrint("📍 Force Update: Memicu pengiriman lokasi awal...");
      await locationProvider.getCurrentLocationWithFraudCheck(user.id);
    } catch (e) {
      debugPrint("⚠️ Force update failed: $e");
    }
  }

  void _showTrackingErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Text("Tracking Gagal"),
          ],
        ),
        content: Text("Error: $error\n\nPastikan GPS aktif dan izin lokasi diberikan."),
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
              _attemptStartServices();
            },
            child: const Text("Coba Lagi"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Gunakan Consumer AuthProvider agar saat user selesai loading, UI me-refresh
    // dan memanggil _attemptStartServices lagi
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Trigger logic start service jika user baru saja loaded
        if (authProvider.user != null && !_servicesStarted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _attemptStartServices();
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
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
              BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    return Consumer2<NetworkProvider, LocationProvider>(
      builder: (context, networkProvider, locationProvider, _) {
        Color statusColor;
        if (!locationProvider.isTracking) {
          statusColor = const Color(0xFFF44336); // Merah (Bahaya/Mati)
        } else if (!networkProvider.isConnected) {
          statusColor = const Color(0xFFFF9800); // Oranye (Offline)
        } else {
          statusColor = const Color(0xFF4CAF50); // Hijau (Aman)
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
                // Tracking Status
                Row(
                  children: [
                    Icon(
                      locationProvider.isTracking ? Icons.gps_fixed : Icons.gps_off,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      locationProvider.isTracking ? 'Tracking ON' : 'Tracking OFF',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (!locationProvider.isTracking)
                      GestureDetector(
                        onTap: _attemptStartServices,
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                          child: const Text("FIX", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      )
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