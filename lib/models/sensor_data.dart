/// Model untuk data sensor yang dikumpulkan bersama lokasi
class SensorData {
  final DateTime timestamp;

  // Accelerometer data
  final double? accelerometerX;
  final double? accelerometerY;
  final double? accelerometerZ;

  // Gyroscope data
  final double? gyroscopeX;
  final double? gyroscopeY;
  final double? gyroscopeZ;

  // Magnetometer data
  final double? magnetometerX;
  final double? magnetometerY;
  final double? magnetometerZ;

  // Barometer (pressure)
  final double? pressure;

  // Light sensor
  final double? lightLevel;

  // Step counter
  final int? stepCount;

  // Battery info
  final int? batteryLevel;
  final bool? isCharging;

  SensorData({
    required this.timestamp,
    this.accelerometerX,
    this.accelerometerY,
    this.accelerometerZ,
    this.gyroscopeX,
    this.gyroscopeY,
    this.gyroscopeZ,
    this.magnetometerX,
    this.magnetometerY,
    this.magnetometerZ,
    this.pressure,
    this.lightLevel,
    this.stepCount,
    this.batteryLevel,
    this.isCharging,
  });

  /// Menghitung magnitude accelerometer
  double? get accelerometerMagnitude {
    if (accelerometerX == null || accelerometerY == null || accelerometerZ == null) {
      return null;
    }
    return _magnitude(accelerometerX!, accelerometerY!, accelerometerZ!);
  }

  /// Menghitung magnitude gyroscope
  double? get gyroscopeMagnitude {
    if (gyroscopeX == null || gyroscopeY == null || gyroscopeZ == null) {
      return null;
    }
    return _magnitude(gyroscopeX!, gyroscopeY!, gyroscopeZ!);
  }

  double _magnitude(double x, double y, double z) {
    return (x * x + y * y + z * z);
  }

  /// Mendeteksi apakah device sedang bergerak berdasarkan accelerometer
  bool get isDeviceMoving {
    final magnitude = accelerometerMagnitude;
    if (magnitude == null) return false;

    // Gravity adalah ~9.8 m/s², jika magnitude berbeda signifikan, berarti bergerak
    const double gravitySquared = 9.8 * 9.8;
    const double threshold = 2.0; // Toleransi

    return (magnitude - gravitySquared).abs() > threshold;
  }

  /// Mendeteksi apakah device sedang diputar
  bool get isDeviceRotating {
    final magnitude = gyroscopeMagnitude;
    if (magnitude == null) return false;

    const double threshold = 0.1;
    return magnitude > threshold;
  }

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      timestamp: DateTime.parse(json['timestamp']),
      accelerometerX: json['accelerometer_x']?.toDouble(),
      accelerometerY: json['accelerometer_y']?.toDouble(),
      accelerometerZ: json['accelerometer_z']?.toDouble(),
      gyroscopeX: json['gyroscope_x']?.toDouble(),
      gyroscopeY: json['gyroscope_y']?.toDouble(),
      gyroscopeZ: json['gyroscope_z']?.toDouble(),
      magnetometerX: json['magnetometer_x']?.toDouble(),
      magnetometerY: json['magnetometer_y']?.toDouble(),
      magnetometerZ: json['magnetometer_z']?.toDouble(),
      pressure: json['pressure']?.toDouble(),
      lightLevel: json['light_level']?.toDouble(),
      stepCount: json['step_count'],
      batteryLevel: json['battery_level'],
      isCharging: json['is_charging'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'accelerometer_x': accelerometerX,
      'accelerometer_y': accelerometerY,
      'accelerometer_z': accelerometerZ,
      'gyroscope_x': gyroscopeX,
      'gyroscope_y': gyroscopeY,
      'gyroscope_z': gyroscopeZ,
      'magnetometer_x': magnetometerX,
      'magnetometer_y': magnetometerY,
      'magnetometer_z': magnetometerZ,
      'pressure': pressure,
      'light_level': lightLevel,
      'step_count': stepCount,
      'battery_level': batteryLevel,
      'is_charging': isCharging,
    };
  }
}

/// Model untuk enhanced location tracking dengan sensor data
class EnhancedLocationTracking {
  final String? id;
  final String userId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final int? batteryLevel;
  final bool isSynced;

  // Sensor data
  final SensorData? sensorData;

  // Device info untuk fraud detection
  final DeviceSecurityInfo? securityInfo;

  // Provider info
  final String? locationProvider; // gps, network, fused

  // Fraud analysis result (filled after analysis)
  final double? trustScore;
  final bool? isFlagged;

  EnhancedLocationTracking({
    this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
    this.accuracy,
    this.speed,
    this.bearing,
    this.batteryLevel,
    this.isSynced = false,
    this.sensorData,
    this.securityInfo,
    this.locationProvider,
    this.trustScore,
    this.isFlagged,
  });

  factory EnhancedLocationTracking.fromJson(Map<String, dynamic> json) {
    return EnhancedLocationTracking(
      id: json['id'],
      userId: json['user_id'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      altitude: json['altitude']?.toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      accuracy: json['accuracy']?.toDouble(),
      speed: json['speed']?.toDouble(),
      bearing: json['bearing']?.toDouble(),
      batteryLevel: json['battery_level'],
      isSynced: json['is_synced'] ?? false,
      sensorData: json['sensor_data'] != null
          ? SensorData.fromJson(json['sensor_data'])
          : null,
      securityInfo: json['security_info'] != null
          ? DeviceSecurityInfo.fromJson(json['security_info'])
          : null,
      locationProvider: json['location_provider'],
      trustScore: json['trust_score']?.toDouble(),
      isFlagged: json['is_flagged'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,
      'speed': speed,
      'bearing': bearing,
      'battery_level': batteryLevel,
      'is_synced': isSynced,
      'sensor_data': sensorData?.toJson(),
      'security_info': securityInfo?.toJson(),
      'location_provider': locationProvider,
      'trust_score': trustScore,
      'is_flagged': isFlagged,
    };
  }

  EnhancedLocationTracking copyWith({
    String? id,
    String? userId,
    double? latitude,
    double? longitude,
    double? altitude,
    DateTime? timestamp,
    double? accuracy,
    double? speed,
    double? bearing,
    int? batteryLevel,
    bool? isSynced,
    SensorData? sensorData,
    DeviceSecurityInfo? securityInfo,
    String? locationProvider,
    double? trustScore,
    bool? isFlagged,
  }) {
    return EnhancedLocationTracking(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      timestamp: timestamp ?? this.timestamp,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      bearing: bearing ?? this.bearing,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isSynced: isSynced ?? this.isSynced,
      sensorData: sensorData ?? this.sensorData,
      securityInfo: securityInfo ?? this.securityInfo,
      locationProvider: locationProvider ?? this.locationProvider,
      trustScore: trustScore ?? this.trustScore,
      isFlagged: isFlagged ?? this.isFlagged,
    );
  }
}

/// Model untuk informasi keamanan device
class DeviceSecurityInfo {
  final bool isMockLocationEnabled;
  final bool isDeviceRooted;
  final bool isEmulator;
  final bool isDeveloperModeEnabled;
  final bool isUsbDebuggingEnabled;
  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;
  final String? deviceId;
  final String? timezone;
  final List<String>? installedMockApps;

  DeviceSecurityInfo({
    this.isMockLocationEnabled = false,
    this.isDeviceRooted = false,
    this.isEmulator = false,
    this.isDeveloperModeEnabled = false,
    this.isUsbDebuggingEnabled = false,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    this.deviceId,
    this.timezone,
    this.installedMockApps,
  });

  /// Menghitung security score (0.0 - 1.0, higher is better)
  double get securityScore {
    double score = 1.0;

    if (isMockLocationEnabled) score -= 0.4;
    if (isDeviceRooted) score -= 0.3;
    if (isEmulator) score -= 0.5;
    if (isDeveloperModeEnabled) score -= 0.1;
    if (isUsbDebuggingEnabled) score -= 0.1;
    if (installedMockApps != null && installedMockApps!.isNotEmpty) {
      score -= 0.3;
    }

    return score.clamp(0.0, 1.0);
  }

  factory DeviceSecurityInfo.fromJson(Map<String, dynamic> json) {
    return DeviceSecurityInfo(
      isMockLocationEnabled: json['is_mock_location_enabled'] ?? false,
      isDeviceRooted: json['is_device_rooted'] ?? false,
      isEmulator: json['is_emulator'] ?? false,
      isDeveloperModeEnabled: json['is_developer_mode_enabled'] ?? false,
      isUsbDebuggingEnabled: json['is_usb_debugging_enabled'] ?? false,
      deviceModel: json['device_model'],
      osVersion: json['os_version'],
      appVersion: json['app_version'],
      deviceId: json['device_id'],
      timezone: json['timezone'],
      installedMockApps: json['installed_mock_apps'] != null
          ? List<String>.from(json['installed_mock_apps'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_mock_location_enabled': isMockLocationEnabled,
      'is_device_rooted': isDeviceRooted,
      'is_emulator': isEmulator,
      'is_developer_mode_enabled': isDeveloperModeEnabled,
      'is_usb_debugging_enabled': isUsbDebuggingEnabled,
      'device_model': deviceModel,
      'os_version': osVersion,
      'app_version': appVersion,
      'device_id': deviceId,
      'timezone': timezone,
      'installed_mock_apps': installedMockApps,
    };
  }
}