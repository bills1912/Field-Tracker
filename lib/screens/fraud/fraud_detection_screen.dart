import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/fraud_detection_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSecurityInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityInfo() async {
    setState(() => _isLoadingSecurityInfo = true);
    try {
      final provider = context.read<FraudDetectionProvider>();
      _securityInfo = await provider.getDeviceSecurityStatus();
    } catch (e) {
      debugPrint('Error loading security info: $e');
    } finally {
      setState(() => _isLoadingSecurityInfo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fraud Detection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSecurityInfo,
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
    return Consumer<FraudDetectionProvider>(
      builder: (context, provider, _) {
        final user = context.read<AuthProvider>().user;
        final stats = user != null
            ? provider.getStatistics(user.id)
            : FraudStatistics.empty();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Monitoring status card
              _buildMonitoringStatusCard(provider),
              const SizedBox(height: 16),

              // Statistics cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Cek',
                      provider.totalAnalyzed.toString(),
                      Icons.analytics,
                      const Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Terdeteksi',
                      provider.totalFlagged.toString(),
                      Icons.warning,
                      const Color(0xFFF44336),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Trust Score',
                      '${(provider.averageTrustScore * 100).toInt()}%',
                      Icons.verified_user,
                      const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Fraud Rate',
                      '${(provider.fraudRate * 100).toStringAsFixed(1)}%',
                      Icons.pie_chart,
                      const Color(0xFFFF9800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Last analysis result
              if (provider.lastResult != null) ...[
                const Text(
                  'Analisis Terakhir',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                FraudAnalysisCard(result: provider.lastResult!),
                const SizedBox(height: 24),
              ],

              // Most common fraud types
              if (provider.recentResults.isNotEmpty) ...[
                const Text(
                  'Jenis Fraud Terbanyak',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildFraudTypesList(provider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonitoringStatusCard(FraudDetectionProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: provider.isMonitoring
                        ? const Color(0xFF4CAF50)
                        : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.isMonitoring
                            ? 'Monitoring Aktif'
                            : 'Monitoring Tidak Aktif',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        provider.isMonitoring
                            ? 'Sensor data sedang dikumpulkan'
                            : 'Aktifkan untuk mulai memantau',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: provider.isMonitoring,
                  onChanged: (value) async {
                    if (value) {
                      await provider.startMonitoring();
                    } else {
                      await provider.stopMonitoring();
                    }
                  },
                  activeColor: const Color(0xFF4CAF50),
                ),
              ],
            ),
            if (provider.error != null) ...[
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
                        provider.error!,
                        style: const TextStyle(
                          color: Color(0xFFF44336),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: provider.clearError,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Belum ada data fraud'),
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
    return Consumer<FraudDetectionProvider>(
      builder: (context, provider, _) {
        if (provider.recentResults.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'Belum ada riwayat analisis',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.recentResults.length,
          itemBuilder: (context, index) {
            final result = provider.recentResults[index];
            return _buildHistoryItem(result);
          },
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
              Text(
                'Detail Analisis',
                style: const TextStyle(
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
              Text(
                'Lokasi',
                style: const TextStyle(
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeviceSecurityStatus(securityInfo: _securityInfo!),
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