/// Model untuk hasil analisis fraud detection lokasi
class LocationFraudResult {
  final String id;
  final String locationId;
  final String userId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  /// Skor kepercayaan (0.0 - 1.0), semakin tinggi semakin terpercaya
  final double trustScore;

  /// Apakah lokasi ini terdeteksi sebagai fraud
  final bool isFraudulent;

  /// List flag yang terdeteksi
  final List<FraudFlag> flags;

  /// Detail analisis
  final FraudAnalysisDetail analysisDetail;

  /// Risk level berdasarkan trust score
  RiskLevel get riskLevel {
    if (trustScore >= 0.8) return RiskLevel.low;
    if (trustScore >= 0.6) return RiskLevel.medium;
    if (trustScore >= 0.4) return RiskLevel.high;
    return RiskLevel.critical;
  }

  LocationFraudResult({
    required this.id,
    required this.locationId,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.trustScore,
    required this.isFraudulent,
    required this.flags,
    required this.analysisDetail,
  });

  factory LocationFraudResult.fromJson(Map<String, dynamic> json) {
    return LocationFraudResult(
      id: json['id'],
      locationId: json['location_id'],
      userId: json['user_id'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      trustScore: json['trust_score'].toDouble(),
      isFraudulent: json['is_fraudulent'],
      flags: (json['flags'] as List)
          .map((f) => FraudFlag.fromJson(f))
          .toList(),
      analysisDetail: FraudAnalysisDetail.fromJson(json['analysis_detail']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'trust_score': trustScore,
      'is_fraudulent': isFraudulent,
      'flags': flags.map((f) => f.toJson()).toList(),
      'analysis_detail': analysisDetail.toJson(),
    };
  }
}

/// Enum untuk level risiko
enum RiskLevel {
  low,      // Trust score >= 0.8
  medium,   // Trust score 0.6 - 0.8
  high,     // Trust score 0.4 - 0.6
  critical  // Trust score < 0.4
}

/// Model untuk flag fraud yang terdeteksi
class FraudFlag {
  final FraudType type;
  final String description;
  final double severity; // 0.0 - 1.0
  final Map<String, dynamic>? metadata;

  FraudFlag({
    required this.type,
    required this.description,
    required this.severity,
    this.metadata,
  });

  factory FraudFlag.fromJson(Map<String, dynamic> json) {
    return FraudFlag(
      type: FraudType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => FraudType.unknown,
      ),
      description: json['description'],
      severity: json['severity'].toDouble(),
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'description': description,
      'severity': severity,
      'metadata': metadata,
    };
  }
}

/// Tipe-tipe fraud yang dapat dideteksi
enum FraudType {
  mockLocation,           // Fake GPS app terdeteksi
  impossibleSpeed,        // Kecepatan tidak mungkin (teleportasi)
  accuracyAnomaly,        // Akurasi GPS tidak wajar
  altitudeAnomaly,        // Ketinggian tidak konsisten
  timestampAnomaly,       // Timestamp mencurigakan
  stationaryTooLong,      // Diam terlalu lama di satu titik
  zigzagPattern,          // Pola pergerakan zigzag tidak wajar
  jumpingLocation,        // Lokasi melompat-lompat
  sensorMismatch,         // Data sensor tidak konsisten
  rootedDevice,           // Device di-root/jailbreak
  emulatorDetected,       // Berjalan di emulator
  timeZoneMismatch,       // Timezone tidak sesuai lokasi
  frequencyAnomaly,       // Frekuensi update tidak wajar
  clusterAnomaly,         // Banyak enumerator di titik yang sama
  nightActivity,          // Aktivitas di luar jam kerja
  weekendActivity,        // Aktivitas di akhir pekan
  boundaryViolation,      // Di luar area kerja yang ditentukan
  unknown
}

/// Detail analisis fraud
class FraudAnalysisDetail {
  // Speed analysis
  final double? speedKmh;
  final double? maxAllowedSpeedKmh;
  final bool isSpeedValid;

  // Accuracy analysis
  final double? gpsAccuracy;
  final bool isAccuracyValid;

  // Movement analysis
  final double? distanceFromPrevious;
  final int? timeSincePrevious;
  final MovementPattern? movementPattern;

  // Sensor analysis
  final bool? accelerometerActive;
  final bool? gyroscopeConsistent;
  final double? sensorConfidence;

  // Device analysis
  final bool? isMockLocationEnabled;
  final bool? isDeviceRooted;
  final bool? isEmulator;

  // Time analysis
  final bool isWithinWorkingHours;
  final bool isWeekday;

  // Historical analysis
  final double? historicalTrustScore;
  final int? totalLocationsToday;
  final int? flaggedLocationsToday;

  FraudAnalysisDetail({
    this.speedKmh,
    this.maxAllowedSpeedKmh,
    this.isSpeedValid = true,
    this.gpsAccuracy,
    this.isAccuracyValid = true,
    this.distanceFromPrevious,
    this.timeSincePrevious,
    this.movementPattern,
    this.accelerometerActive,
    this.gyroscopeConsistent,
    this.sensorConfidence,
    this.isMockLocationEnabled,
    this.isDeviceRooted,
    this.isEmulator,
    this.isWithinWorkingHours = true,
    this.isWeekday = true,
    this.historicalTrustScore,
    this.totalLocationsToday,
    this.flaggedLocationsToday,
  });

  factory FraudAnalysisDetail.fromJson(Map<String, dynamic> json) {
    return FraudAnalysisDetail(
      speedKmh: json['speed_kmh']?.toDouble(),
      maxAllowedSpeedKmh: json['max_allowed_speed_kmh']?.toDouble(),
      isSpeedValid: json['is_speed_valid'] ?? true,
      gpsAccuracy: json['gps_accuracy']?.toDouble(),
      isAccuracyValid: json['is_accuracy_valid'] ?? true,
      distanceFromPrevious: json['distance_from_previous']?.toDouble(),
      timeSincePrevious: json['time_since_previous'],
      movementPattern: json['movement_pattern'] != null
          ? MovementPattern.values.firstWhere(
            (e) => e.name == json['movement_pattern'],
        orElse: () => MovementPattern.unknown,
      )
          : null,
      accelerometerActive: json['accelerometer_active'],
      gyroscopeConsistent: json['gyroscope_consistent'],
      sensorConfidence: json['sensor_confidence']?.toDouble(),
      isMockLocationEnabled: json['is_mock_location_enabled'],
      isDeviceRooted: json['is_device_rooted'],
      isEmulator: json['is_emulator'],
      isWithinWorkingHours: json['is_within_working_hours'] ?? true,
      isWeekday: json['is_weekday'] ?? true,
      historicalTrustScore: json['historical_trust_score']?.toDouble(),
      totalLocationsToday: json['total_locations_today'],
      flaggedLocationsToday: json['flagged_locations_today'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speed_kmh': speedKmh,
      'max_allowed_speed_kmh': maxAllowedSpeedKmh,
      'is_speed_valid': isSpeedValid,
      'gps_accuracy': gpsAccuracy,
      'is_accuracy_valid': isAccuracyValid,
      'distance_from_previous': distanceFromPrevious,
      'time_since_previous': timeSincePrevious,
      'movement_pattern': movementPattern?.name,
      'accelerometer_active': accelerometerActive,
      'gyroscope_consistent': gyroscopeConsistent,
      'sensor_confidence': sensorConfidence,
      'is_mock_location_enabled': isMockLocationEnabled,
      'is_device_rooted': isDeviceRooted,
      'is_emulator': isEmulator,
      'is_within_working_hours': isWithinWorkingHours,
      'is_weekday': isWeekday,
      'historical_trust_score': historicalTrustScore,
      'total_locations_today': totalLocationsToday,
      'flagged_locations_today': flaggedLocationsToday,
    };
  }
}

/// Pola pergerakan yang terdeteksi
enum MovementPattern {
  normal,       // Pergerakan wajar
  stationary,   // Diam di tempat
  walking,      // Jalan kaki
  driving,      // Berkendara
  erratic,      // Tidak menentu
  zigzag,       // Zigzag mencurigakan
  teleporting,  // Lompat lokasi
  unknown
}

/// Extension untuk mendapatkan warna berdasarkan risk level
extension RiskLevelExtension on RiskLevel {
  String get displayName {
    switch (this) {
      case RiskLevel.low:
        return 'Risiko Rendah';
      case RiskLevel.medium:
        return 'Risiko Sedang';
      case RiskLevel.high:
        return 'Risiko Tinggi';
      case RiskLevel.critical:
        return 'Risiko Kritis';
    }
  }

  String get colorHex {
    switch (this) {
      case RiskLevel.low:
        return '#4CAF50';
      case RiskLevel.medium:
        return '#FF9800';
      case RiskLevel.high:
        return '#F44336';
      case RiskLevel.critical:
        return '#9C27B0';
    }
  }
}

/// Extension untuk mendapatkan deskripsi fraud type
extension FraudTypeExtension on FraudType {
  String get displayName {
    switch (this) {
      case FraudType.mockLocation:
        return 'Fake GPS Terdeteksi';
      case FraudType.impossibleSpeed:
        return 'Kecepatan Tidak Mungkin';
      case FraudType.accuracyAnomaly:
        return 'Akurasi GPS Tidak Wajar';
      case FraudType.altitudeAnomaly:
        return 'Ketinggian Tidak Konsisten';
      case FraudType.timestampAnomaly:
        return 'Timestamp Mencurigakan';
      case FraudType.stationaryTooLong:
        return 'Diam Terlalu Lama';
      case FraudType.zigzagPattern:
        return 'Pola Zigzag Mencurigakan';
      case FraudType.jumpingLocation:
        return 'Lokasi Melompat';
      case FraudType.sensorMismatch:
        return 'Data Sensor Tidak Konsisten';
      case FraudType.rootedDevice:
        return 'Perangkat Di-root';
      case FraudType.emulatorDetected:
        return 'Emulator Terdeteksi';
      case FraudType.timeZoneMismatch:
        return 'Timezone Tidak Sesuai';
      case FraudType.frequencyAnomaly:
        return 'Frekuensi Update Tidak Wajar';
      case FraudType.clusterAnomaly:
        return 'Anomali Cluster';
      case FraudType.nightActivity:
        return 'Aktivitas Malam Hari';
      case FraudType.weekendActivity:
        return 'Aktivitas Akhir Pekan';
      case FraudType.boundaryViolation:
        return 'Di Luar Area Kerja';
      case FraudType.unknown:
        return 'Tidak Diketahui';
    }
  }
}