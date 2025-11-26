import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/fraud_detection_provider.dart'; // 🆕 NEW
import '../surveys/surveys_list_screen.dart';
import '../map/map_screen.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../fraud/fraud_detection_screen.dart'; // 🆕 NEW

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 🆕 UPDATED: Added FraudDetectionScreen to the list
  final List<Widget> _screens = [
    const SurveysListScreen(),
    const MapScreen(),
    const FraudDetectionScreen(), // 🆕 NEW - Replaced ChatScreen
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 🆕 NEW: Start fraud detection monitoring when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFraudDetection();
    });
  }

  // 🆕 NEW: Initialize fraud detection
  Future<void> _initializeFraudDetection() async {
    try {
      final fraudProvider = context.read<FraudDetectionProvider>();
      await fraudProvider.startMonitoring();
      debugPrint('✅ Fraud detection monitoring started');
    } catch (e) {
      debugPrint('⚠️ Error starting fraud detection: $e');
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final networkProvider = context.watch<NetworkProvider>();
    final fraudProvider = context.watch<FraudDetectionProvider>(); // 🆕 NEW

    return Scaffold(
      body: Stack(
        children: [
          // Main content - display current screen
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // Online/Offline indicator at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: networkProvider.isConnected ? 0 : 32,
                color: networkProvider.isConnected
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFF44336),
                child: networkProvider.isConnected
                    ? null
                    : Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Offline Mode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF2196F3),
          unselectedItemColor: Colors.grey[600],
          selectedFontSize: 12,
          unselectedFontSize: 12,
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 0 ? Icons.poll : Icons.poll_outlined,
              ),
              label: 'Surveys',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 1 ? Icons.map : Icons.map_outlined,
              ),
              label: 'Map',
            ),
            // 🆕 UPDATED: Changed from Chat to Security/Fraud
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  Icon(
                    _currentIndex == 2
                        ? Icons.security
                        : Icons.security_outlined,
                  ),
                  // 🆕 NEW: Show badge if fraud detected
                  if (fraudProvider.totalFlagged > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '${fraudProvider.totalFlagged > 9 ? "9+" : fraudProvider.totalFlagged}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Security',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                _currentIndex == 3 ? Icons.person : Icons.person_outline,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}// TODO Implement this library.