import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/fraud_detection_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/location_fraud_result.dart';
import '../../models/sensor_data.dart';
import '../../widgets/fraud_detection_widgets.dart';

/// Screen untuk monitoring fraud detection
class FraudDetectionScreen extends StatefulWidget {
  const FraudDetectionScreen({super.key});

  @override
  State<FraudDetectionScreen> createState() => _FraudDetectionScreenState();
}

class _FraudDetectionScreenState extends State<FraudDetectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingSecurityInfo = false;
  DeviceSecurityInfo? _securityInfo;
  bool _isRunningInitialCheck = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Load security info dan jalankan initial fraud check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSecurityInfo();
      _runInitialFraudCheck();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityInfo() async {
    if (!mounted) return;
    setState(() => _isLoadingSecurityInfo = true);
    try {
      final provider = context.read<FraudDetectionProvider>();
      _securityInfo = await provider.getDeviceSecurityStatus();
    } catch (e) {
      debugPrint('Error loading security info: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSecurityInfo = false);
      }
    }
  }

  /// 🆕 Jalankan fraud check saat screen dibuka untuk memastikan data terupdate
  Future<void> _runInitialFraudCheck() async {
    if (!mounted || _isRunningInitialCheck) return;

    setState(() => _isRunningInitialCheck = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final locationProvider = context.read<LocationProvider>();
      final fraudProvider = context.read<FraudDetectionProvider>();

      final user = authProvider.user;
      if (user == null) {
        debugPrint('⚠️ FraudDetectionScreen: No user logged in');
        return;
      }

      // Pastikan monitoring aktif
      if (!fraudProvider.isMonitoring) {
        debugPrint('🚀 FraudDetectionScreen: Starting fraud monitoring...');
        await fraudProvider.startMonitoring();
      }

      // Jalankan fraud check dengan lokasi saat ini
      debugPrint('🔍 FraudDetectionScreen: Running initial fraud check...');
      final (location, fraudResult) = await locationProvider.getCurrentLocationWithFraudCheck(user.id);

      if (fraudResult != null) {
        debugPrint('✅ Initial fraud check completed:');
        debugPrint('   Trust Score: ${fraudResult.trustScore}');
        debugPrint('   Is Fraudulent: ${fraudResult.isFraudulent}');
        debugPrint('   Flags: ${fraudResult.flags.length}');
      }

    } catch (e) {
      debugPrint('❌ Error running initial fraud check: $e');
    } finally {
      if (mounted) {
        setState(() => _isRunningInitialCheck = false);
      }
    }
  }

  /// Refresh semua data
  Future<void> _refreshAll() async {
    await _loadSecurityInfo();
    await _runInitialFraudCheck();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fraud Detection'),
        actions: [
          if (_isRunningInitialCheck || _isLoadingSecurityInfo)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
              tooltip: 'Refresh & Check',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'History', icon: Icon(Icons.history)),
            Tab(text: 'Device', icon: Icon(Icons.phone_android)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildHistoryTab(),
          _buildDeviceTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Consumer2<FraudDetectionProvider, LocationProvider>(
      builder: (context, fraudProvider, locationProvider, _) {
        final user = context.read<AuthProvider>().user;
        final stats = user != null
            ? fraudProvider.getStatistics(user.id)
            : FraudStatistics.empty();

        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🆕 UPDATED: Status card tanpa toggle (read-only)
                _buildProtectionStatusCard(fraudProvider, locationProvider),
                const SizedBox(height: 16),

                // Statistics cards
                // Row(
                //   children: [
                //     Expanded(
                //       child: _buildStatCard(
                //         'Total Cek',
                //         fraudProvider.totalAnalyzed.toString(),
                //         Icons.analytics,
                //         const Color(0xFF2196F3),
                //       ),
                //     ),
                //     const SizedBox(width: 12),
                //     Expanded(
                //       child: _buildStatCard(
                //         'Terdeteksi',
                //         fraudProvider.totalFlagged.toString(),
                //         Icons.warning,
                //         fraudProvider.totalFlagged > 0
                //             ? const Color(0xFFF44336)
                //             : const Color(0xFF4CAF50),
                //       ),
                //     ),
                //   ],
                // ),
                // const SizedBox(height: 12),
                // Row(
                //   children: [
                //     Expanded(
                //       child: _buildStatCard(
                //         'Trust Score',
                //         '${(fraudProvider.averageTrustScore * 100).toInt()}%',
                //         Icons.verified_user,
                //         _getTrustScoreColor(fraudProvider.averageTrustScore),
                //       ),
                //     ),
                //     const SizedBox(width: 12),
                //     Expanded(
                //       child: _buildStatCard(
                //         'Fraud Rate',
                //         '${(fraudProvider.fraudRate * 100).toStringAsFixed(1)}%',
                //         Icons.pie_chart,
                //         fraudProvider.fraudRate > 0.1
                //             ? const Color(0xFFF44336)
                //             : const Color(0xFF4CAF50),
                //       ),
                //     ),
                //   ],
                // ),
                // const SizedBox(height: 24),

                // 🆕 Device Security Quick Status
                if (_securityInfo != null) ...[
                  _buildDeviceSecurityQuickStatus(_securityInfo!),
                  const SizedBox(height: 24),
                ],

                // Last analysis result
                if (fraudProvider.lastResult != null) ...[
                  const Text(
                    'Analisis Terakhir',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FraudAnalysisCard(result: fraudProvider.lastResult!),
                  const SizedBox(height: 24),
                ] else if (locationProvider.lastFraudResult != null) ...[
                  // Fallback ke LocationProvider jika FraudProvider kosong
                  const Text(
                    'Analisis Terakhir',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FraudAnalysisCard(result: locationProvider.lastFraudResult!),
                  const SizedBox(height: 24),
                ] else ...[
                  // No analysis yet - show prompt
                  _buildNoAnalysisPrompt(),
                  const SizedBox(height: 24),
                ],

                // Most common fraud types
                if (fraudProvider.recentResults.isNotEmpty) ...[
                  const Text(
                    'Jenis Fraud Terbanyak',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFraudTypesList(fraudProvider),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 🆕 NEW: Protection status card tanpa toggle
  Widget _buildProtectionStatusCard(
      FraudDetectionProvider fraudProvider,
      LocationProvider locationProvider,
      ) {
    final isMonitoring = fraudProvider.isMonitoring;
    final isTracking = locationProvider.isTracking;
    final isFullyProtected = isMonitoring && isTracking;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Status icon
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
                            ? 'Protection Aktif'
                            : 'Protection Tidak Lengkap',
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
                            ? 'Sensor & lokasi sedang dipantau'
                            : 'Beberapa service tidak aktif',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // 🔒 Status indicator (bukan toggle)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isFullyProtected
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFF44336),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isFullyProtected ? 'ON' : 'OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
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
                      'Monitoring otomatis aktif saat aplikasi dibuka. Tidak dapat dinonaktifkan.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Error display
            if (fraudProvider.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Color(0xFFF44336), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fraudProvider.error!,
                        style: const TextStyle(
                          color: Color(0xFFF44336),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: fraudProvider.clearError,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],

            // Fix button if not fully protected
            if (!isFullyProtected) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _refreshAll,
                  icon: const Icon(Icons.build, size: 18),
                  label: const Text('Aktifkan Protection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 🆕 NEW: Device security quick status untuk overview
  Widget _buildDeviceSecurityQuickStatus(DeviceSecurityInfo securityInfo) {
    final hasIssues = securityInfo.isMockLocationEnabled ||
        securityInfo.isDeviceRooted ||
        securityInfo.isEmulator ||
        (securityInfo.installedMockApps?.isNotEmpty ?? false);

    return Card(
      color: hasIssues ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasIssues ? Icons.warning : Icons.verified_user,
                  color: hasIssues
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                ),
                const SizedBox(width: 8),
                Text(
                  hasIssues ? 'Perangkat Berisiko' : 'Perangkat Aman',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: hasIssues
                        ? const Color(0xFFF44336)
                        : const Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
            if (hasIssues) ...[
              const SizedBox(height: 12),
              if (securityInfo.isEmulator)
                _buildQuickIssueItem('Emulator terdeteksi'),
              if (securityInfo.isMockLocationEnabled)
                _buildQuickIssueItem('Mock location aktif'),
              if (securityInfo.isDeviceRooted)
                _buildQuickIssueItem('Device di-root'),
              if (securityInfo.installedMockApps?.isNotEmpty ?? false)
                _buildQuickIssueItem(
                    'Fake GPS apps: ${securityInfo.installedMockApps!.length}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickIssueItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.cancel, size: 14, color: Color(0xFFF44336)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFFF44336)),
          ),
        ],
      ),
    );
  }

  /// 🆕 NEW: Prompt ketika belum ada analisis
  Widget _buildNoAnalysisPrompt() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Belum Ada Analisis',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tekan tombol refresh untuk menjalankan analisis fraud detection pada lokasi saat ini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isRunningInitialCheck ? null : _refreshAll,
              icon: _isRunningInitialCheck
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.play_arrow),
              label: Text(_isRunningInitialCheck ? 'Menganalisis...' : 'Jalankan Analisis'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTrustScoreColor(double score) {
    if (score >= 0.8) return const Color(0xFF4CAF50);
    if (score >= 0.6) return const Color(0xFFFF9800);
    if (score >= 0.4) return const Color(0xFFF44336);
    return const Color(0xFF9C27B0);
  }

  Widget _buildStatCard(
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFraudTypesList(FraudDetectionProvider provider) {
    final commonTypes = provider.getMostCommonFraudTypes();

    if (commonTypes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[400]),
              const SizedBox(width: 12),
              const Text('Tidak ada fraud terdeteksi'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: commonTypes.map((entry) {
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF44336).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${entry.value}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF44336),
                  ),
                ),
              ),
            ),
            title: Text(
              entry.key.displayName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Consumer2<FraudDetectionProvider, LocationProvider>(
      builder: (context, fraudProvider, locationProvider, _) {
        // 🆕 Gabungkan hasil dari kedua provider
        final List<LocationFraudResult> allResults = [
          ...fraudProvider.recentResults,
          ...locationProvider.fraudHistory,
        ];

        // Deduplicate dan sort by timestamp
        final Map<String, LocationFraudResult> uniqueResults = {};
        for (var result in allResults) {
          final key = '${result.timestamp.millisecondsSinceEpoch}_${result.latitude}_${result.longitude}';
          if (!uniqueResults.containsKey(key)) {
            uniqueResults[key] = result;
          }
        }

        final sortedResults = uniqueResults.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (sortedResults.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada riwayat analisis',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tarik ke bawah untuk menjalankan analisis',
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isRunningInitialCheck ? null : _refreshAll,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Jalankan Analisis'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedResults.length,
            itemBuilder: (context, index) {
              final result = sortedResults[index];
              return _buildHistoryItem(result);
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(LocationFraudResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showResultDetail(result),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: result.isFraudulent
                      ? const Color(0xFFFFEBEE)
                      : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  result.isFraudulent ? Icons.warning : Icons.check_circle,
                  color: result.isFraudulent
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(result.timestamp),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        RiskLevelBadge(
                          riskLevel: result.riskLevel,
                          fontSize: 10,
                          showIcon: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Trust: ${(result.trustScore * 100).toInt()}% • ${result.flags.length} flags',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (result.flags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        result.flags.map((f) => f.type.displayName).take(2).join(', '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showResultDetail(LocationFraudResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Detail Analisis',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                DateFormat('dd MMMM yyyy, HH:mm:ss').format(result.timestamp),
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              FraudAnalysisCard(result: result),
              const SizedBox(height: 20),
              const Text(
                'Lokasi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF2196F3)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${result.latitude.toStringAsFixed(6)}, ${result.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceTab() {
    if (_isLoadingSecurityInfo) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_securityInfo == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Gagal memuat info perangkat',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              onPressed: _loadSecurityInfo,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final provider = context.read<FraudDetectionProvider>();
        _securityInfo = await provider.getDeviceSecurityStatus();
        if (mounted) setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeviceSecurityStatus(
              securityInfo: _securityInfo!,
              onRefresh: () async {
                setState(() => _isLoadingSecurityInfo = true);
                final provider = context.read<FraudDetectionProvider>();
                _securityInfo = await provider.getDeviceSecurityStatus();
                if (mounted) {
                  setState(() => _isLoadingSecurityInfo = false);
                }
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Tips Keamanan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildSecurityTip(
              Icons.gps_off,
              'Matikan Mock Location',
              'Pastikan fitur mock location dinonaktifkan di pengaturan developer',
            ),
            _buildSecurityTip(
              Icons.security,
              'Jangan Root Device',
              'Device yang di-root lebih rentan terhadap manipulasi lokasi',
            ),
            _buildSecurityTip(
              Icons.apps,
              'Hapus Fake GPS Apps',
              'Uninstall aplikasi fake GPS yang mungkin terinstal',
            ),
            _buildSecurityTip(
              Icons.update,
              'Update Aplikasi',
              'Selalu gunakan versi terbaru untuk keamanan optimal',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityTip(IconData icon, String title, String description) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF2196F3)),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          description,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ),
    );
  }
}