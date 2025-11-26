import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/fraud_detection_provider.dart'; // 🆕 NEW
import '../../models/user.dart';
import '../../models/sensor_data.dart'; // 🆕 NEW
import '../../widgets/fraud_detection_widgets.dart'; // 🆕 NEW
import '../auth/onboarding_screen.dart'; // 🔧 FIX: Changed from login_screen to onboarding_screen

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoggingOut = false;
  String? _verificationCode;
  final TextEditingController _codeController = TextEditingController();

  // 🆕 NEW: Device security info
  DeviceSecurityInfo? _securityInfo;
  bool _isLoadingSecurityInfo = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceSecurityInfo(); // 🆕 NEW
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // 🆕 NEW: Load device security info
  Future<void> _loadDeviceSecurityInfo() async {
    setState(() => _isLoadingSecurityInfo = true);
    try {
      final fraudProvider = context.read<FraudDetectionProvider>();
      _securityInfo = await fraudProvider.getDeviceSecurityStatus();
    } catch (e) {
      debugPrint('Error loading security info: $e');
    } finally {
      setState(() => _isLoadingSecurityInfo = false);
    }
  }

  /// Toggle location tracking with improved error handling
  Future<void> _toggleLocationTracking(bool value) async {
    final locationProvider = context.read<LocationProvider>();
    final user = context.read<AuthProvider>().user;

    if (user == null) {
      _showError('User not found');
      return;
    }

    try {
      if (value) {
        _showLoadingDialog('Starting location tracking...');
        // 🆕 UPDATED: Use tracking with fraud detection
        await locationProvider.startTrackingWithFraudDetection(user.id);
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Location tracking with fraud detection started'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        await locationProvider.stopTracking();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Location tracking stopped'),
                ],
              ),
              backgroundColor: Colors.grey,
            ),
          );
        }
      }
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      String errorMessage = 'Failed to toggle location tracking';
      String actionMessage = '';
      bool showSettings = false;

      if (e.toString().contains('PERMISSION_DENIED_FOREVER')) {
        errorMessage = 'Location permission permanently denied';
        actionMessage = 'Please enable location permission in app settings';
        showSettings = true;
      } else if (e.toString().contains('PERMISSION_DENIED')) {
        errorMessage = 'Location permission denied';
        actionMessage = 'Location permission is required for tracking';
      } else if (e.toString().contains('Location service')) {
        errorMessage = 'Location service disabled';
        actionMessage = 'Please enable GPS in your device settings';
        showSettings = true;
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }

      if (mounted) {
        _showErrorDialog(
          errorMessage,
          actionMessage,
          showSettings: showSettings,
        );
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorDialog(String title, String message, {bool showSettings = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Error')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message),
            ],
          ],
        ),
        actions: [
          if (showSettings)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    _verificationCode = (100 + (900 * (DateTime.now().millisecond / 1000))).toInt().toString();
    _codeController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Logout',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Apakah yakin logout?',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _verificationCode!,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: Color(0xFF1976D2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Untuk melakukan aksi berikut, tolong ketik kode verifikasi dengan benar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 3,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '000',
                counterText: '',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('BATAL'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmLogout,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('LOGOUT'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    if (_codeController.text != _verificationCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect verification code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(context);
    setState(() => _isLoggingOut = true);

    try {
      // Stop location tracking
      final locationProvider = context.read<LocationProvider>();
      if (locationProvider.isTracking) {
        await locationProvider.stopTracking();
      }

      // 🆕 NEW: Stop fraud detection monitoring
      final fraudProvider = context.read<FraudDetectionProvider>();
      if (fraudProvider.isMonitoring) {
        await fraudProvider.stopMonitoring();
      }

      // Logout
      final authProvider = context.read<AuthProvider>();
      await authProvider.logout();

      if (mounted) {
        // 🔧 FIX: Navigate to OnboardingScreen instead of LoginScreen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Logout error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final networkProvider = context.watch<NetworkProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final fraudProvider = context.watch<FraudDetectionProvider>(); // 🆕 NEW

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person, size: 40, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          user?.username ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: const TextStyle(fontSize: 14, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1976D2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            user?.role.name.toUpperCase() ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // 🆕 NEW: Device Security Status Section
                _buildSection(
                  'Keamanan Perangkat',
                  [
                    if (_isLoadingSecurityInfo)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_securityInfo != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: _buildSecuritySummary(_securityInfo!),
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.refresh, color: Color(0xFF2196F3)),
                        title: const Text('Load Security Info'),
                        onTap: _loadDeviceSecurityInfo,
                      ),
                  ],
                ),

                _buildSection(
                  'Location Tracking',
                  [
                    _buildSwitchTile(
                      icon: Icons.my_location,
                      title: 'Background Tracking',
                      subtitle: locationProvider.isTracking
                          ? 'Tracking with fraud detection active'
                          : 'Enable to track location',
                      value: locationProvider.isTracking,
                      onChanged: _toggleLocationTracking,
                    ),
                    // 🆕 NEW: Fraud Detection Toggle
                    _buildSwitchTile(
                      icon: Icons.security,
                      title: 'Fraud Detection',
                      subtitle: locationProvider.isFraudDetectionEnabled
                          ? 'Location fraud detection active'
                          : 'Enable for extra security',
                      value: locationProvider.isFraudDetectionEnabled,
                      onChanged: (value) {
                        locationProvider.setFraudDetectionEnabled(value);
                      },
                    ),
                  ],
                ),

                // 🆕 NEW: Fraud Statistics
                if (fraudProvider.totalAnalyzed > 0)
                  _buildSection(
                    'Fraud Statistics',
                    [
                      ListTile(
                        leading: const Icon(Icons.analytics, color: Color(0xFF2196F3)),
                        title: const Text('Total Analyzed'),
                        trailing: Text(
                          '${fraudProvider.totalAnalyzed}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.warning,
                          color: fraudProvider.totalFlagged > 0
                              ? const Color(0xFFF44336)
                              : Colors.grey,
                        ),
                        title: const Text('Flagged Locations'),
                        trailing: Text(
                          '${fraudProvider.totalFlagged}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: fraudProvider.totalFlagged > 0
                                ? const Color(0xFFF44336)
                                : Colors.grey,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.verified_user, color: Color(0xFF4CAF50)),
                        title: const Text('Average Trust Score'),
                        trailing: Text(
                          '${(fraudProvider.averageTrustScore * 100).toInt()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: fraudProvider.averageTrustScore >= 0.7
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF9800),
                          ),
                        ),
                      ),
                    ],
                  ),

                _buildSection(
                  'Sync Status',
                  [
                    ListTile(
                      leading: Icon(
                        networkProvider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: networkProvider.isConnected
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9800),
                      ),
                      title: Text(
                        networkProvider.isConnected ? 'Online' : 'Offline',
                      ),
                      subtitle: Text(
                        networkProvider.pendingSync > 0
                            ? '${networkProvider.pendingSync} items pending sync'
                            : 'All data synced',
                      ),
                      trailing: networkProvider.pendingSync > 0
                          ? ElevatedButton.icon(
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Sync Now'),
                        onPressed: networkProvider.syncNow,
                      )
                          : null,
                    ),
                  ],
                ),
                _buildSection(
                  'About',
                  [
                    _buildInfoTile('App Version', '1.0.0'),
                    _buildInfoTile('User ID', user?.id.substring(0, 8) ?? ''),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    icon: _isLoggingOut
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Icon(Icons.logout),
                    label: Text(_isLoggingOut ? 'Logging out...' : 'Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF44336),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    onPressed: _isLoggingOut ? null : _showLogoutDialog,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Field Data Collection Tracker',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      Text(
                        'Built with Flutter + Anti-Fraud System',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🆕 NEW: Build security summary widget
  Widget _buildSecuritySummary(DeviceSecurityInfo info) {
    final isSecure = info.securityScore >= 0.7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSecure
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isSecure ? Icons.verified_user : Icons.warning,
                color: isSecure
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFF44336),
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSecure ? 'Perangkat Aman' : 'Perangkat Berisiko',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSecure
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFF44336),
                      ),
                    ),
                    Text(
                      'Security Score: ${(info.securityScore * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadDeviceSecurityInfo,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSecurityItem(
                'Mock GPS',
                !info.isMockLocationEnabled,
              ),
              _buildSecurityItem(
                'Root',
                !info.isDeviceRooted,
              ),
              _buildSecurityItem(
                'Emulator',
                !info.isEmulator,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityItem(String label, bool isOk) {
    return Column(
      children: [
        Icon(
          isOk ? Icons.check_circle : Icons.cancel,
          color: isOk ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2196F3)),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF2196F3),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Color(0xFF666666))),
      trailing: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF333333),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}