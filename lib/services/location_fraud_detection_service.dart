import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/location_fraud_result.dart';
import '../models/sensor_data.dart';
import '../models/location_tracking.dart';
import 'sensor_collector_service.dart';
import 'storage_service.dart';

/// Service utama untuk mendeteksi fraud pada data lokasi
class LocationFraudDetectionService {
  static LocationFraudDetectionService? _instance;
  static LocationFraudDetectionService get instance =>
      _instance ??= LocationFraudDetectionService._();

  LocationFraudDetectionService._();

  // Konfigurasi threshold
  final FraudDetectionConfig config = FraudDetectionConfig();

  // Cache untuk lokasi sebelumnya per user
  final Map<String, List<EnhancedLocationTracking>> _locationCache = {};

  // Cache untuk hasil fraud detection
  final Map<String, LocationFraudResult> _fraudResultCache = {};

  /// Analyze a location for potential fraud
  Future<LocationFraudResult> analyzeLocation({
    required EnhancedLocationTracking location,
    List<EnhancedLocationTracking>? previousLocations,
  }) async {
    final List<FraudFlag> flags = [];
    double trustScore = 1.0;

    // Get previous locations from cache if not provided
    previousLocations ??= _locationCache[location.userId] ?? [];

    // Get device security info
    DeviceSecurityInfo? securityInfo = location.securityInfo;
    securityInfo ??= await SensorCollectorService.instance.getDeviceSecurityInfo();

    // ===== 1. Device Security Checks =====
    final deviceFlags = _checkDeviceSecurity(securityInfo);
    flags.addAll(deviceFlags);
    trustScore -= deviceFlags.fold(0.0, (sum, flag) => sum + flag.severity * 0.5);

    // ===== 2. GPS Accuracy Check =====
    final accuracyFlag = _checkGpsAccuracy(location.accuracy);
    if (accuracyFlag != null) {
      flags.add(accuracyFlag);
      trustScore -= accuracyFlag.severity * 0.3;
    }

    // ===== 3. Speed Analysis =====
    if (previousLocations.isNotEmpty) {
      final lastLocation = previousLocations.last;
      final speedFlag = _checkSpeed(location, lastLocation);
      if (speedFlag != null) {
        flags.add(speedFlag);
        trustScore -= speedFlag.severity * 0.4;
      }
    }

    // ===== 4. Movement Pattern Analysis =====
    if (previousLocations.length >= 3) {
      final patternFlags = _analyzeMovementPattern(location, previousLocations);
      flags.addAll(patternFlags);
      trustScore -= patternFlags.fold(0.0, (sum, flag) => sum + flag.severity * 0.3);
    }

    // ===== 5. Sensor Consistency Check =====
    if (location.sensorData != null && previousLocations.isNotEmpty) {
      final sensorFlag = _checkSensorConsistency(location, previousLocations.last);
      if (sensorFlag != null) {
        flags.add(sensorFlag);
        trustScore -= sensorFlag.severity * 0.3;
      }
    }

    // ===== 6. Time-based Checks =====
    final timeFlags = _checkTimeConstraints(location.timestamp);
    flags.addAll(timeFlags);
    trustScore -= timeFlags.fold(0.0, (sum, flag) => sum + flag.severity * 0.2);

    // ===== 7. Altitude Consistency =====
    if (location.altitude != null && previousLocations.isNotEmpty) {
      final altitudeFlag = _checkAltitudeConsistency(location, previousLocations);
      if (altitudeFlag != null) {
        flags.add(altitudeFlag);
        trustScore -= altitudeFlag.severity * 0.2;
      }
    }

    // ===== 8. Frequency Analysis =====
    if (previousLocations.length >= 2) {
      final frequencyFlag = _checkUpdateFrequency(location, previousLocations);
      if (frequencyFlag != null) {
        flags.add(frequencyFlag);
        trustScore -= frequencyFlag.severity * 0.2;
      }
    }

    // Clamp trust score
    trustScore = trustScore.clamp(0.0, 1.0);

    // Determine if fraudulent based on trust score and flags
    final isFraudulent = trustScore < config.fraudThreshold ||
        flags.any((f) => f.severity >= 0.8);

    // Build analysis detail
    final analysisDetail = _buildAnalysisDetail(
      location: location,
      previousLocations: previousLocations,
      securityInfo: securityInfo,
    );

    // Create result
    final result = LocationFraudResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      locationId: location.id ?? '',
      userId: location.userId,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: location.timestamp,
      trustScore: trustScore,
      isFraudulent: isFraudulent,
      flags: flags,
      analysisDetail: analysisDetail,
    );

    // Update cache
    _updateCache(location);
    _fraudResultCache[location.id ?? ''] = result;

    // Log result
    _logAnalysisResult(result);

    return result;
  }

  /// Check device security indicators
  List<FraudFlag> _checkDeviceSecurity(DeviceSecurityInfo securityInfo) {
    final flags = <FraudFlag>[];

    if (securityInfo.isMockLocationEnabled) {
      flags.add(FraudFlag(
        type: FraudType.mockLocation,
        description: 'Mock location / Fake GPS terdeteksi aktif pada perangkat',
        severity: 1.0,
        metadata: {'source': 'device_settings'},
      ));
    }

    if (securityInfo.isDeviceRooted) {
      flags.add(FraudFlag(
        type: FraudType.rootedDevice,
        description: 'Perangkat terdeteksi di-root/jailbreak',
        severity: 0.7,
        metadata: {'risk': 'high'},
      ));
    }

    if (securityInfo.isEmulator) {
      flags.add(FraudFlag(
        type: FraudType.emulatorDetected,
        description: 'Aplikasi berjalan di emulator/simulator',
        severity: 1.0,
        metadata: {'device_type': 'emulator'},
      ));
    }

    if (securityInfo.installedMockApps != null &&
        securityInfo.installedMockApps!.isNotEmpty) {
      flags.add(FraudFlag(
        type: FraudType.mockLocation,
        description: 'Aplikasi fake GPS terdeteksi terinstal: ${securityInfo.installedMockApps!.join(", ")}',
        severity: 0.8,
        metadata: {'apps': securityInfo.installedMockApps},
      ));
    }

    return flags;
  }

  /// Check GPS accuracy for anomalies
  FraudFlag? _checkGpsAccuracy(double? accuracy) {
    if (accuracy == null) return null;

    // Accuracy terlalu sempurna (< 1 meter) sangat mencurigakan
    if (accuracy < config.minRealisticAccuracy) {
      return FraudFlag(
        type: FraudType.accuracyAnomaly,
        description: 'Akurasi GPS terlalu sempurna (${accuracy.toStringAsFixed(1)}m), tidak realistis untuk GPS biasa',
        severity: 0.9,
        metadata: {'accuracy': accuracy, 'threshold': config.minRealisticAccuracy},
      );
    }

    // Accuracy terlalu buruk juga mencurigakan
    if (accuracy > config.maxAcceptableAccuracy) {
      return FraudFlag(
        type: FraudType.accuracyAnomaly,
        description: 'Akurasi GPS terlalu buruk (${accuracy.toStringAsFixed(1)}m)',
        severity: 0.5,
        metadata: {'accuracy': accuracy, 'threshold': config.maxAcceptableAccuracy},
      );
    }

    return null;
  }

  /// Check speed between two locations
  FraudFlag? _checkSpeed(
      EnhancedLocationTracking current,
      EnhancedLocationTracking previous,
      ) {
    final distance = _calculateDistance(
      current.latitude,
      current.longitude,
      previous.latitude,
      previous.longitude,
    );

    final timeSeconds = current.timestamp.difference(previous.timestamp).inSeconds;
    if (timeSeconds <= 0) return null;

    final speedKmh = (distance / 1000) / (timeSeconds / 3600);

    // Check for impossible speed (teleportation)
    if (speedKmh > config.maxPossibleSpeedKmh) {
      return FraudFlag(
        type: FraudType.impossibleSpeed,
        description: 'Kecepatan tidak mungkin: ${speedKmh.toStringAsFixed(1)} km/jam (teleportasi terdeteksi)',
        severity: 1.0,
        metadata: {
          'speed_kmh': speedKmh,
          'distance_m': distance,
          'time_seconds': timeSeconds,
          'max_allowed': config.maxPossibleSpeedKmh,
        },
      );
    }

    // Check for unrealistic speed (very high but not impossible)
    if (speedKmh > config.maxRealisticSpeedKmh) {
      return FraudFlag(
        type: FraudType.impossibleSpeed,
        description: 'Kecepatan tidak realistis: ${speedKmh.toStringAsFixed(1)} km/jam',
        severity: 0.7,
        metadata: {
          'speed_kmh': speedKmh,
          'distance_m': distance,
          'time_seconds': timeSeconds,
        },
      );
    }

    return null;
  }

  /// Analyze movement pattern for anomalies
  List<FraudFlag> _analyzeMovementPattern(
      EnhancedLocationTracking current,
      List<EnhancedLocationTracking> previousLocations,
      ) {
    final flags = <FraudFlag>[];

    // Take last N locations for pattern analysis
    final recentLocations = previousLocations.length > 10
        ? previousLocations.sublist(previousLocations.length - 10)
        : previousLocations;

    // Check for zigzag pattern
    if (recentLocations.length >= 4) {
      final zigzagScore = _calculateZigzagScore([...recentLocations, current]);
      if (zigzagScore > config.zigzagThreshold) {
        flags.add(FraudFlag(
          type: FraudType.zigzagPattern,
          description: 'Pola pergerakan zigzag tidak wajar terdeteksi',
          severity: 0.6,
          metadata: {'zigzag_score': zigzagScore},
        ));
      }
    }

    // Check for jumping locations
    if (recentLocations.length >= 2) {
      final jumpCount = _countLocationJumps([...recentLocations, current]);
      if (jumpCount > config.maxAllowedJumps) {
        flags.add(FraudFlag(
          type: FraudType.jumpingLocation,
          description: 'Lokasi melompat-lompat tidak wajar ($jumpCount kali)',
          severity: 0.7,
          metadata: {'jump_count': jumpCount},
        ));
      }
    }

    // Check for stationary too long
    if (recentLocations.length >= 5) {
      final isStationary = _checkStationaryPattern([...recentLocations, current]);
      if (isStationary.isStationary && isStationary.durationMinutes > config.maxStationaryMinutes) {
        flags.add(FraudFlag(
          type: FraudType.stationaryTooLong,
          description: 'Diam di satu lokasi terlalu lama (${isStationary.durationMinutes} menit)',
          severity: 0.4,
          metadata: {
            'duration_minutes': isStationary.durationMinutes,
            'location': '${isStationary.latitude}, ${isStationary.longitude}',
          },
        ));
      }
    }

    return flags;
  }

  /// Check sensor consistency between location updates
  FraudFlag? _checkSensorConsistency(
      EnhancedLocationTracking current,
      EnhancedLocationTracking previous,
      ) {
    if (current.sensorData == null || previous.sensorData == null) {
      return null;
    }

    final distance = _calculateDistance(
      current.latitude,
      current.longitude,
      previous.latitude,
      previous.longitude,
    );

    // If device moved significantly but sensors show no movement
    if (distance > 100) { // More than 100 meters
      final currentSensor = current.sensorData!;

      // Check if accelerometer shows no movement
      if (!currentSensor.isDeviceMoving && !currentSensor.isDeviceRotating) {
        return FraudFlag(
          type: FraudType.sensorMismatch,
          description: 'GPS menunjukkan perpindahan ${distance.toStringAsFixed(0)}m, tetapi sensor tidak mendeteksi gerakan',
          severity: 0.8,
          metadata: {
            'distance_m': distance,
            'accelerometer_active': currentSensor.isDeviceMoving,
            'gyroscope_active': currentSensor.isDeviceRotating,
          },
        );
      }
    }

    return null;
  }

  /// Check time-based constraints
  List<FraudFlag> _checkTimeConstraints(DateTime timestamp) {
    final flags = <FraudFlag>[];

    // Check if outside working hours
    final hour = timestamp.hour;
    if (hour < config.workingHoursStart || hour >= config.workingHoursEnd) {
      flags.add(FraudFlag(
        type: FraudType.nightActivity,
        description: 'Aktivitas di luar jam kerja (${hour.toString().padLeft(2, '0')}:00)',
        severity: 0.3,
        metadata: {
          'hour': hour,
          'working_hours': '${config.workingHoursStart}:00 - ${config.workingHoursEnd}:00',
        },
      ));
    }

    // Check if weekend
    if (timestamp.weekday == DateTime.saturday || timestamp.weekday == DateTime.sunday) {
      flags.add(FraudFlag(
        type: FraudType.weekendActivity,
        description: 'Aktivitas di akhir pekan',
        severity: 0.2,
        metadata: {'weekday': timestamp.weekday},
      ));
    }

    return flags;
  }

  /// Check altitude consistency
  FraudFlag? _checkAltitudeConsistency(
      EnhancedLocationTracking current,
      List<EnhancedLocationTracking> previousLocations,
      ) {
    if (current.altitude == null) return null;

    final recentWithAltitude = previousLocations
        .where((l) => l.altitude != null)
        .take(5)
        .toList();

    if (recentWithAltitude.isEmpty) return null;

    // Calculate average altitude
    final avgAltitude = recentWithAltitude
        .map((l) => l.altitude!)
        .reduce((a, b) => a + b) / recentWithAltitude.length;

    final altitudeDiff = (current.altitude! - avgAltitude).abs();

    // If altitude changed drastically without significant horizontal movement
    if (altitudeDiff > config.maxAltitudeChangeMeters) {
      final lastLocation = previousLocations.last;
      final horizontalDistance = _calculateDistance(
        current.latitude,
        current.longitude,
        lastLocation.latitude,
        lastLocation.longitude,
      );

      // If horizontal movement is small but altitude changed a lot
      if (horizontalDistance < 500) { // Less than 500m
        return FraudFlag(
          type: FraudType.altitudeAnomaly,
          description: 'Perubahan ketinggian tidak wajar: ${altitudeDiff.toStringAsFixed(1)}m',
          severity: 0.5,
          metadata: {
            'altitude_diff': altitudeDiff,
            'horizontal_distance': horizontalDistance,
            'current_altitude': current.altitude,
            'avg_altitude': avgAltitude,
          },
        );
      }
    }

    return null;
  }

  /// Check update frequency
  FraudFlag? _checkUpdateFrequency(
      EnhancedLocationTracking current,
      List<EnhancedLocationTracking> previousLocations,
      ) {
    if (previousLocations.length < 2) return null;

    // Calculate intervals between last few updates
    final intervals = <int>[];
    for (int i = 1; i < previousLocations.length && i <= 5; i++) {
      final interval = previousLocations[i].timestamp
          .difference(previousLocations[i - 1].timestamp)
          .inSeconds;
      intervals.add(interval);
    }

    // Add current interval
    intervals.add(
      current.timestamp.difference(previousLocations.last.timestamp).inSeconds,
    );

    // Check for unnaturally regular intervals (exactly same interval = suspicious)
    final firstInterval = intervals.first;
    final allSame = intervals.every((i) => (i - firstInterval).abs() < 2);

    if (allSame && intervals.length >= 3) {
      return FraudFlag(
        type: FraudType.frequencyAnomaly,
        description: 'Interval update terlalu teratur (${firstInterval}s), kemungkinan otomatis',
        severity: 0.4,
        metadata: {
          'intervals': intervals,
          'pattern': 'too_regular',
        },
      );
    }

    return null;
  }

  /// Build analysis detail object
  FraudAnalysisDetail _buildAnalysisDetail({
    required EnhancedLocationTracking location,
    required List<EnhancedLocationTracking> previousLocations,
    required DeviceSecurityInfo securityInfo,
  }) {
    double? speedKmh;
    double? distanceFromPrevious;
    int? timeSincePrevious;

    if (previousLocations.isNotEmpty) {
      final lastLocation = previousLocations.last;
      distanceFromPrevious = _calculateDistance(
        location.latitude,
        location.longitude,
        lastLocation.latitude,
        lastLocation.longitude,
      );
      timeSincePrevious = location.timestamp
          .difference(lastLocation.timestamp)
          .inSeconds;

      if (timeSincePrevious > 0) {
        speedKmh = (distanceFromPrevious / 1000) / (timeSincePrevious / 3600);
      }
    }

    return FraudAnalysisDetail(
      speedKmh: speedKmh,
      maxAllowedSpeedKmh: config.maxPossibleSpeedKmh,
      isSpeedValid: speedKmh == null || speedKmh <= config.maxPossibleSpeedKmh,
      gpsAccuracy: location.accuracy,
      isAccuracyValid: location.accuracy == null ||
          (location.accuracy! >= config.minRealisticAccuracy &&
              location.accuracy! <= config.maxAcceptableAccuracy),
      distanceFromPrevious: distanceFromPrevious,
      timeSincePrevious: timeSincePrevious,
      accelerometerActive: location.sensorData?.isDeviceMoving,
      gyroscopeConsistent: location.sensorData?.isDeviceRotating,
      isMockLocationEnabled: securityInfo.isMockLocationEnabled,
      isDeviceRooted: securityInfo.isDeviceRooted,
      isEmulator: securityInfo.isEmulator,
      isWithinWorkingHours: _isWithinWorkingHours(location.timestamp),
      isWeekday: _isWeekday(location.timestamp),
      totalLocationsToday: _countLocationsToday(location.userId),
      flaggedLocationsToday: _countFlaggedLocationsToday(location.userId),
    );
  }

  // ===== Helper Methods =====

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const double earthRadius = 6371000; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Calculate zigzag score (higher = more zigzag)
  double _calculateZigzagScore(List<EnhancedLocationTracking> locations) {
    if (locations.length < 3) return 0.0;

    int directionChanges = 0;
    double? previousBearing;

    for (int i = 1; i < locations.length; i++) {
      final bearing = _calculateBearing(
        locations[i - 1].latitude,
        locations[i - 1].longitude,
        locations[i].latitude,
        locations[i].longitude,
      );

      if (previousBearing != null) {
        final bearingDiff = (bearing - previousBearing).abs();
        // If direction changed more than 90 degrees
        if (bearingDiff > 90 && bearingDiff < 270) {
          directionChanges++;
        }
      }
      previousBearing = bearing;
    }

    return directionChanges / (locations.length - 2);
  }

  /// Calculate bearing between two points
  double _calculateBearing(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    final dLon = _toRadians(lon2 - lon1);
    final y = sin(dLon) * cos(_toRadians(lat2));
    final x = cos(_toRadians(lat1)) * sin(_toRadians(lat2)) -
        sin(_toRadians(lat1)) * cos(_toRadians(lat2)) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// Count sudden location jumps
  int _countLocationJumps(List<EnhancedLocationTracking> locations) {
    int jumps = 0;

    for (int i = 1; i < locations.length; i++) {
      final distance = _calculateDistance(
        locations[i - 1].latitude,
        locations[i - 1].longitude,
        locations[i].latitude,
        locations[i].longitude,
      );

      final timeSeconds = locations[i].timestamp
          .difference(locations[i - 1].timestamp)
          .inSeconds;

      if (timeSeconds > 0) {
        final speedKmh = (distance / 1000) / (timeSeconds / 3600);
        if (speedKmh > config.maxRealisticSpeedKmh) {
          jumps++;
        }
      }
    }

    return jumps;
  }

  /// Check if locations show stationary pattern
  ({bool isStationary, int durationMinutes, double latitude, double longitude})
  _checkStationaryPattern(List<EnhancedLocationTracking> locations) {
    if (locations.isEmpty) {
      return (isStationary: false, durationMinutes: 0, latitude: 0, longitude: 0);
    }

    // Calculate center point
    double sumLat = 0, sumLon = 0;
    for (var loc in locations) {
      sumLat += loc.latitude;
      sumLon += loc.longitude;
    }
    final centerLat = sumLat / locations.length;
    final centerLon = sumLon / locations.length;

    // Check if all points are within small radius
    bool allNearCenter = true;
    for (var loc in locations) {
      final distance = _calculateDistance(
        loc.latitude,
        loc.longitude,
        centerLat,
        centerLon,
      );
      if (distance > config.stationaryRadiusMeters) {
        allNearCenter = false;
        break;
      }
    }

    if (allNearCenter) {
      final durationMinutes = locations.last.timestamp
          .difference(locations.first.timestamp)
          .inMinutes;
      return (
      isStationary: true,
      durationMinutes: durationMinutes,
      latitude: centerLat,
      longitude: centerLon,
      );
    }

    return (isStationary: false, durationMinutes: 0, latitude: 0, longitude: 0);
  }

  bool _isWithinWorkingHours(DateTime timestamp) {
    final hour = timestamp.hour;
    return hour >= config.workingHoursStart && hour < config.workingHoursEnd;
  }

  bool _isWeekday(DateTime timestamp) {
    return timestamp.weekday >= DateTime.monday &&
        timestamp.weekday <= DateTime.friday;
  }

  int _countLocationsToday(String userId) {
    final today = DateTime.now();
    return (_locationCache[userId] ?? [])
        .where((l) =>
    l.timestamp.year == today.year &&
        l.timestamp.month == today.month &&
        l.timestamp.day == today.day)
        .length;
  }

  int _countFlaggedLocationsToday(String userId) {
    // This would query from local database in production
    return 0;
  }

  void _updateCache(EnhancedLocationTracking location) {
    _locationCache[location.userId] ??= [];
    _locationCache[location.userId]!.add(location);

    // Keep only last 100 locations per user
    if (_locationCache[location.userId]!.length > 100) {
      _locationCache[location.userId]!.removeAt(0);
    }
  }

  void _logAnalysisResult(LocationFraudResult result) {
    final emoji = result.isFraudulent ? '🚨' : '✅';
    debugPrint('$emoji Fraud Analysis: Trust=${result.trustScore.toStringAsFixed(2)}, '
        'Flags=${result.flags.length}, Risk=${result.riskLevel.displayName}');

    for (var flag in result.flags) {
      debugPrint('   ⚠️ ${flag.type.displayName}: ${flag.description}');
    }
  }

  /// Clear cache for a specific user
  void clearUserCache(String userId) {
    _locationCache.remove(userId);
  }

  /// Clear all caches
  void clearAllCaches() {
    _locationCache.clear();
    _fraudResultCache.clear();
  }

  /// Get fraud history for a user
  List<LocationFraudResult> getFraudHistory(String userId) {
    return _fraudResultCache.values
        .where((r) => r.userId == userId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }
}

/// Configuration for fraud detection thresholds
class FraudDetectionConfig {
  // Speed thresholds
  final double maxPossibleSpeedKmh;
  final double maxRealisticSpeedKmh;

  // Accuracy thresholds
  final double minRealisticAccuracy;
  final double maxAcceptableAccuracy;

  // Pattern thresholds
  final double zigzagThreshold;
  final int maxAllowedJumps;
  final int maxStationaryMinutes;
  final double stationaryRadiusMeters;

  // Altitude threshold
  final double maxAltitudeChangeMeters;

  // Time constraints
  final int workingHoursStart;
  final int workingHoursEnd;

  // Overall fraud threshold
  final double fraudThreshold;

  FraudDetectionConfig({
    this.maxPossibleSpeedKmh = 200.0,   // Above this = teleportation
    this.maxRealisticSpeedKmh = 120.0,  // Above this = suspicious
    this.minRealisticAccuracy = 1.0,     // Below this = fake GPS
    this.maxAcceptableAccuracy = 100.0,  // Above this = poor signal
    this.zigzagThreshold = 0.7,          // 70% direction changes
    this.maxAllowedJumps = 2,            // Max sudden jumps
    this.maxStationaryMinutes = 120,     // 2 hours max stationary
    this.stationaryRadiusMeters = 20.0,  // Within 20m = same location
    this.maxAltitudeChangeMeters = 100.0,// Max altitude change
    this.workingHoursStart = 6,          // 6 AM
    this.workingHoursEnd = 22,           // 10 PM
    this.fraudThreshold = 0.5,           // Below 0.5 = fraud
  });

  /// Create config with custom values
  FraudDetectionConfig copyWith({
    double? maxPossibleSpeedKmh,
    double? maxRealisticSpeedKmh,
    double? minRealisticAccuracy,
    double? maxAcceptableAccuracy,
    double? zigzagThreshold,
    int? maxAllowedJumps,
    int? maxStationaryMinutes,
    double? stationaryRadiusMeters,
    double? maxAltitudeChangeMeters,
    int? workingHoursStart,
    int? workingHoursEnd,
    double? fraudThreshold,
  }) {
    return FraudDetectionConfig(
      maxPossibleSpeedKmh: maxPossibleSpeedKmh ?? this.maxPossibleSpeedKmh,
      maxRealisticSpeedKmh: maxRealisticSpeedKmh ?? this.maxRealisticSpeedKmh,
      minRealisticAccuracy: minRealisticAccuracy ?? this.minRealisticAccuracy,
      maxAcceptableAccuracy: maxAcceptableAccuracy ?? this.maxAcceptableAccuracy,
      zigzagThreshold: zigzagThreshold ?? this.zigzagThreshold,
      maxAllowedJumps: maxAllowedJumps ?? this.maxAllowedJumps,
      maxStationaryMinutes: maxStationaryMinutes ?? this.maxStationaryMinutes,
      stationaryRadiusMeters: stationaryRadiusMeters ?? this.stationaryRadiusMeters,
      maxAltitudeChangeMeters: maxAltitudeChangeMeters ?? this.maxAltitudeChangeMeters,
      workingHoursStart: workingHoursStart ?? this.workingHoursStart,
      workingHoursEnd: workingHoursEnd ?? this.workingHoursEnd,
      fraudThreshold: fraudThreshold ?? this.fraudThreshold,
    );
  }
}