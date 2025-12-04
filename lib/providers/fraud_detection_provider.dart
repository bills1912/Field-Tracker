import 'package:flutter/foundation.dart';
import '../models/location_fraud_result.dart';
import '../models/sensor_data.dart';
import '../services/location_fraud_detection_service.dart';
import '../services/sensor_collector_service.dart';

/// Provider untuk mengelola state fraud detection
/// 🔒 Fraud detection tidak bisa dimatikan oleh user
class FraudDetectionProvider with ChangeNotifier {
  // Services
  final LocationFraudDetectionService _fraudService = LocationFraudDetectionService.instance;
  final SensorCollectorService _sensorService = SensorCollectorService.instance;

  // State
  bool _isMonitoring = false;
  bool _isAnalyzing = false;
  LocationFraudResult? _lastResult;
  List<LocationFraudResult> _recentResults = [];
  String? _error;

  // Statistics
  int _totalAnalyzed = 0;
  int _totalFlagged = 0;
  double _averageTrustScore = 1.0;

  // 🆕 Cached device security info untuk quick access
  DeviceSecurityInfo? _cachedSecurityInfo;

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get isAnalyzing => _isAnalyzing;
  LocationFraudResult? get lastResult => _lastResult;
  List<LocationFraudResult> get recentResults => _recentResults;
  String? get error => _error;
  int get totalAnalyzed => _totalAnalyzed;
  int get totalFlagged => _totalFlagged;
  double get averageTrustScore => _averageTrustScore;
  double get fraudRate => _totalAnalyzed > 0 ? _totalFlagged / _totalAnalyzed : 0.0;
  DeviceSecurityInfo? get cachedSecurityInfo => _cachedSecurityInfo;

  /// Start monitoring (sensor collection)
  /// 🆕 Dipanggil otomatis saat login
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      debugPrint('⚠️ Fraud monitoring already active');
      return;
    }

    try {
      _error = null;
      debugPrint('🚀 Starting fraud detection monitoring...');

      await _sensorService.startCollecting();
      _isMonitoring = true;

      // 🆕 Refresh device security info saat start
      await _refreshDeviceSecurityInfo();

      debugPrint('✅ Fraud detection monitoring started');
      notifyListeners();
    } catch (e) {
      _error = 'Failed to start monitoring: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  /// Stop monitoring
  /// 🆕 Dipanggil otomatis saat logout
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      debugPrint('🛑 Stopping fraud detection monitoring...');

      await _sensorService.stopCollecting();
      _isMonitoring = false;

      debugPrint('✅ Fraud detection monitoring stopped');
      notifyListeners();
    } catch (e) {
      _error = 'Failed to stop monitoring: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  /// 🆕 Refresh device security info
  Future<void> _refreshDeviceSecurityInfo() async {
    try {
      _cachedSecurityInfo = await _sensorService.refreshDeviceSecurityInfo();
      debugPrint('✅ Device security info refreshed');
      debugPrint('   - Emulator: ${_cachedSecurityInfo?.isEmulator}');
      debugPrint('   - Mock Location: ${_cachedSecurityInfo?.isMockLocationEnabled}');
      debugPrint('   - Rooted: ${_cachedSecurityInfo?.isDeviceRooted}');
    } catch (e) {
      debugPrint('⚠️ Failed to refresh device security info: $e');
    }
  }

  /// Analyze a location for fraud
  Future<LocationFraudResult> analyzeLocation(
      EnhancedLocationTracking location,
      ) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      // Add current sensor data if monitoring
      EnhancedLocationTracking enrichedLocation = location;
      if (_isMonitoring) {
        final sensorData = _sensorService.getCurrentSensorData();
        final securityInfo = await _sensorService.getDeviceSecurityInfo();

        // 🆕 Update cached security info
        _cachedSecurityInfo = securityInfo;

        enrichedLocation = location.copyWith(
          sensorData: sensorData,
          securityInfo: securityInfo,
        );
      }

      // Perform analysis
      final result = await _fraudService.analyzeLocation(
        location: enrichedLocation,
      );

      // Update state
      _lastResult = result;
      _recentResults.insert(0, result);
      if (_recentResults.length > 50) {
        _recentResults.removeLast();
      }

      // Update statistics
      _totalAnalyzed++;
      if (result.isFraudulent) {
        _totalFlagged++;
      }
      _updateAverageTrustScore(result.trustScore);

      _isAnalyzing = false;
      notifyListeners();

      debugPrint('📊 Fraud analysis completed:');
      debugPrint('   Trust Score: ${result.trustScore}');
      debugPrint('   Is Fraudulent: ${result.isFraudulent}');
      debugPrint('   Flags: ${result.flags.length}');

      return result;
    } catch (e) {
      _error = 'Analysis failed: $e';
      _isAnalyzing = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Quick check without full analysis (for real-time validation)
  Future<QuickFraudCheck> quickCheck(
      double latitude,
      double longitude,
      double? accuracy,
      ) async {
    // Check accuracy
    if (accuracy != null && accuracy < 1.0) {
      return QuickFraudCheck(
        isPotentiallyFraudulent: true,
        reason: 'Akurasi GPS terlalu sempurna',
        confidence: 0.9,
      );
    }

    // Check device security
    final securityInfo = await _sensorService.getDeviceSecurityInfo();

    // 🆕 Update cached security info
    _cachedSecurityInfo = securityInfo;

    if (securityInfo.isMockLocationEnabled) {
      return QuickFraudCheck(
        isPotentiallyFraudulent: true,
        reason: 'Mock location terdeteksi',
        confidence: 1.0,
      );
    }

    if (securityInfo.isEmulator) {
      return QuickFraudCheck(
        isPotentiallyFraudulent: true,
        reason: 'Emulator terdeteksi',
        confidence: 1.0,
      );
    }

    if (securityInfo.isDeviceRooted) {
      return QuickFraudCheck(
        isPotentiallyFraudulent: true,
        reason: 'Device di-root',
        confidence: 0.7,
      );
    }

    return QuickFraudCheck(
      isPotentiallyFraudulent: false,
      reason: 'Tidak ada anomali terdeteksi',
      confidence: 0.8,
    );
  }

  /// Get device security status
  Future<DeviceSecurityInfo> getDeviceSecurityStatus() async {
    final securityInfo = await _sensorService.refreshDeviceSecurityInfo();
    _cachedSecurityInfo = securityInfo;
    notifyListeners();
    return securityInfo;
  }

  /// Get fraud statistics for a user
  FraudStatistics getStatistics(String userId) {
    final userResults = _recentResults.where((r) => r.userId == userId).toList();

    if (userResults.isEmpty) {
      return FraudStatistics.empty();
    }

    final flaggedCount = userResults.where((r) => r.isFraudulent).length;
    final avgTrustScore = userResults
        .map((r) => r.trustScore)
        .reduce((a, b) => a + b) / userResults.length;

    // Count flag types
    final flagCounts = <FraudType, int>{};
    for (var result in userResults) {
      for (var flag in result.flags) {
        flagCounts[flag.type] = (flagCounts[flag.type] ?? 0) + 1;
      }
    }

    // Determine risk level
    RiskLevel riskLevel;
    if (avgTrustScore >= 0.8) {
      riskLevel = RiskLevel.low;
    } else if (avgTrustScore >= 0.6) {
      riskLevel = RiskLevel.medium;
    } else if (avgTrustScore >= 0.4) {
      riskLevel = RiskLevel.high;
    } else {
      riskLevel = RiskLevel.critical;
    }

    return FraudStatistics(
      userId: userId,
      totalChecks: userResults.length,
      flaggedCount: flaggedCount,
      averageTrustScore: avgTrustScore,
      riskLevel: riskLevel,
      flagTypeCounts: flagCounts,
      lastChecked: userResults.first.timestamp,
    );
  }

  /// Get most common fraud types
  List<MapEntry<FraudType, int>> getMostCommonFraudTypes() {
    final counts = <FraudType, int>{};

    for (var result in _recentResults) {
      for (var flag in result.flags) {
        counts[flag.type] = (counts[flag.type] ?? 0) + 1;
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(5).toList();
  }

  /// 🆕 Add result from external source (e.g., LocationProvider)
  void addExternalResult(LocationFraudResult result) {
    // Check if result already exists (by timestamp and location)
    final exists = _recentResults.any((r) =>
    r.timestamp == result.timestamp &&
        r.latitude == result.latitude &&
        r.longitude == result.longitude);

    if (!exists) {
      _lastResult = result;
      _recentResults.insert(0, result);
      if (_recentResults.length > 50) {
        _recentResults.removeLast();
      }

      // Update statistics
      _totalAnalyzed++;
      if (result.isFraudulent) {
        _totalFlagged++;
      }
      _updateAverageTrustScore(result.trustScore);

      notifyListeners();
    }
  }

  /// Clear history
  void clearHistory() {
    _recentResults.clear();
    _lastResult = null;
    _totalAnalyzed = 0;
    _totalFlagged = 0;
    _averageTrustScore = 1.0;
    _fraudService.clearAllCaches();
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _updateAverageTrustScore(double newScore) {
    // Rolling average
    if (_totalAnalyzed <= 1) {
      _averageTrustScore = newScore;
    } else {
      _averageTrustScore = ((_averageTrustScore * (_totalAnalyzed - 1)) + newScore) / _totalAnalyzed;
    }
  }
}

/// Result of quick fraud check
class QuickFraudCheck {
  final bool isPotentiallyFraudulent;
  final String reason;
  final double confidence;

  QuickFraudCheck({
    required this.isPotentiallyFraudulent,
    required this.reason,
    required this.confidence,
  });
}

/// Statistics for fraud detection
class FraudStatistics {
  final String userId;
  final int totalChecks;
  final int flaggedCount;
  final double averageTrustScore;
  final RiskLevel riskLevel;
  final Map<FraudType, int> flagTypeCounts;
  final DateTime? lastChecked;

  FraudStatistics({
    required this.userId,
    required this.totalChecks,
    required this.flaggedCount,
    required this.averageTrustScore,
    required this.riskLevel,
    required this.flagTypeCounts,
    this.lastChecked,
  });

  factory FraudStatistics.empty() {
    return FraudStatistics(
      userId: '',
      totalChecks: 0,
      flaggedCount: 0,
      averageTrustScore: 1.0,
      riskLevel: RiskLevel.low,
      flagTypeCounts: {},
    );
  }

  double get fraudRate => totalChecks > 0 ? flaggedCount / totalChecks : 0.0;
}