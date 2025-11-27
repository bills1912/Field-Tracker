import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../surveys/surveys_list_screen.dart';
// import '../map/map_screen.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const SurveysListScreen(),
    // const MapScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  final List<String> _titles = [
    'Surveys',
    'Map',
    'Chat',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Network Status Bar
          Consumer<NetworkProvider>(
            builder: (context, networkProvider, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                color: networkProvider.isConnected
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF9800),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        networkProvider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        networkProvider.isConnected
                            ? 'Online'
                            : 'Offline${networkProvider.pendingSync > 0 ? " • ${networkProvider.pendingSync} pending sync" : ""}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Main Content
          Expanded(
            child: _screens[_currentIndex],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2196F3),
        unselectedItemColor: const Color(0xFF666666),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.poll),
            label: 'Surveys',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}