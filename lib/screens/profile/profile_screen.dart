import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/fraud_detection_provider.dart';
import '../../models/user.dart';
import '../../models/sensor_data.dart';
import '../../widgets/fraud_detection_widgets.dart';
import '../auth/onboarding_screen.dart';

/// Profile Screen yang dimodifikasi
/// 🔒 Toggle tracking DIHAPUS - tracking selalu aktif saat user login
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoggingOut = false;
  String? _verificationCode;
  final TextEditingController _codeController = TextEditingController();

  // Device security info
  DeviceSecurityInfo? _securityInfo;
  bool _isLoadingSecurityInfo = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceSecurityInfo();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

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
            const SizedBox(height: 12),
            // 🆕 Warning tentang tracking
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tracking lokasi dan fraud detection akan dihentikan saat logout.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
      // 🆕 Logout akan otomatis stop semua services
      final authProvider = context.read<AuthProvider>();
      await authProvider.logout();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout error: $e'),
            backgroundColor: Colors.red,
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
    final fraudProvider = context.watch<FraudDetectionProvider>();

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
                // 🆕 Tracking Status Card - READ ONLY (tanpa toggle)
                _buildProtectionStatusCard(locationProvider, fraudProvider),

                // Device Security Status Section
                // _buildSection(
                //   'Keamanan Perangkat',
                //   [
                //     if (_isLoadingSecurityInfo)
                //       const Padding(
                //         padding: EdgeInsets.all(16),
                //         child: Center(child: CircularProgressIndicator()),
                //       )
                //     else if (_securityInfo != null)
                //       Padding(
                //         padding: const EdgeInsets.all(8),
                //         child: _buildSecuritySummary(_securityInfo!),
                //       )
                //     else
                //       ListTile(
                //         leading: const Icon(Icons.refresh, color: Color(0xFF2196F3)),
                //         title: const Text('Load Security Info'),
                //         onTap: _loadDeviceSecurityInfo,
                //       ),
                //   ],
                // ),

                // Fraud Statistics
                if (fraudProvider.totalAnalyzed > 0)
                  _buildSection(
                    'Fraud Statistics',
                    [
                      ListTile(
                        leading: const Icon(Icons.analytics, color: Color(0xFF2196F3)),
                        title: const Text('Total Analyzed'),
                        trailing: Text(
                          '${fraudProvider.totalAnalyzed}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                      title: Text(networkProvider.isConnected ? 'Online' : 'Offline'),
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

  /// 🆕 NEW: Build protection status card - READ ONLY (tidak ada toggle)
  Widget _buildProtectionStatusCard(
      LocationProvider locationProvider,
      FraudDetectionProvider fraudProvider,
      ) {
    final isFullyProtected = locationProvider.isTracking && fraudProvider.isMonitoring;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isFullyProtected
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isFullyProtected ? Icons.security : Icons.security_outlined,
                      color: isFullyProtected
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFF44336),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isFullyProtected
                              ? 'Fully Protected'
                              : 'Protection Incomplete',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isFullyProtected
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFF44336),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isFullyProtected
                              ? 'Lokasi dan aktivitas Anda dipantau'
                              : 'Beberapa service tidak aktif',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 🔒 Status dot (bukan toggle)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFullyProtected
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFF44336),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 🔒 Info box - menjelaskan bahwa tracking tidak bisa dimatikan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tracking otomatis aktif untuk memastikan integritas data survei. Fitur ini tidak dapat dinonaktifkan.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Status details
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatusItem(
                    'GPS',
                    locationProvider.isTracking,
                    Icons.gps_fixed,
                  ),
                  _buildStatusItem(
                    'Fraud',
                    fraudProvider.isMonitoring,
                    Icons.security,
                  ),
                  _buildStatusItem(
                    'Sensors',
                    fraudProvider.isMonitoring,
                    Icons.sensors,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, bool isActive, IconData icon) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        Icon(
          isActive ? Icons.check_circle : Icons.cancel,
          color: isActive ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
          size: 14,
        ),
      ],
    );
  }

  // Widget _buildSecuritySummary(DeviceSecurityInfo info) {
  //   final isSecure = info.securityScore >= 0.7;
  //
  //   return Container(
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       color: isSecure ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Column(
  //       children: [
  //         Row(
  //           children: [
  //             Icon(
  //               isSecure ? Icons.verified_user : Icons.warning,
  //               color: isSecure ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
  //               size: 32,
  //             ),
  //             const SizedBox(width: 12),
  //             Expanded(
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   Text(
  //                     isSecure ? 'Perangkat Aman' : 'Perangkat Berisiko',
  //                     style: TextStyle(
  //                       fontWeight: FontWeight.bold,
  //                       fontSize: 16,
  //                       color: isSecure
  //                           ? const Color(0xFF4CAF50)
  //                           : const Color(0xFFF44336),
  //                     ),
  //                   ),
  //                   Text(
  //                     'Security Score: ${(info.securityScore * 100).toInt()}%',
  //                     style: TextStyle(fontSize: 13, color: Colors.grey[600]),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             IconButton(
  //               icon: const Icon(Icons.refresh),
  //               onPressed: _loadDeviceSecurityInfo,
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: 12),
  //         Row(
  //           mainAxisAlignment: MainAxisAlignment.spaceAround,
  //           children: [
  //             _buildSecurityItem('Mock GPS', !info.isMockLocationEnabled),
  //             _buildSecurityItem('Root', !info.isDeviceRooted),
  //             _buildSecurityItem('Emulator', !info.isEmulator),
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

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
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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