import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/sensor_data.dart';

/// Service untuk mengumpulkan data sensor device
class SensorCollectorService {
  static SensorCollectorService? _instance;
  static SensorCollectorService get instance => _instance ??= SensorCollectorService._();

  SensorCollectorService._();

  // Stream subscriptions
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  // Latest sensor values
  AccelerometerEvent? _lastAccelerometer;
  GyroscopeEvent? _lastGyroscope;
  MagnetometerEvent? _lastMagnetometer;

  // Sensor data buffer for analysis
  final List<SensorData> _sensorBuffer = [];
  static const int _maxBufferSize = 100;

  // Device info
  DeviceSecurityInfo? _cachedSecurityInfo;

  /// Start collecting sensor data
  Future<void> startCollecting() async {
    try {
      // Accelerometer
      _accelerometerSubscription = accelerometerEvents.listen(
            (AccelerometerEvent event) {
          _lastAccelerometer = event;
        },
        onError: (error) {
          debugPrint('Accelerometer error: $error');
        },
      );

      // Gyroscope
      _gyroscopeSubscription = gyroscopeEvents.listen(
            (GyroscopeEvent event) {
          _lastGyroscope = event;
        },
        onError: (error) {
          debugPrint('Gyroscope error: $error');
        },
      );

      // Magnetometer
      _magnetometerSubscription = magnetometerEvents.listen(
            (MagnetometerEvent event) {
          _lastMagnetometer = event;
        },
        onError: (error) {
          debugPrint('Magnetometer error: $error');
        },
      );

      debugPrint('✅ Sensor collection started');
    } catch (e) {
      debugPrint('❌ Error starting sensor collection: $e');
    }
  }

  /// Stop collecting sensor data
  Future<void> stopCollecting() async {
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _magnetometerSubscription?.cancel();

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _magnetometerSubscription = null;

    debugPrint('✅ Sensor collection stopped');
  }

  /// Get current sensor snapshot
  SensorData getCurrentSensorData() {
    final now = DateTime.now();

    return SensorData(
      timestamp: now,
      accelerometerX: _lastAccelerometer?.x,
      accelerometerY: _lastAccelerometer?.y,
      accelerometerZ: _lastAccelerometer?.z,
      gyroscopeX: _lastGyroscope?.x,
      gyroscopeY: _lastGyroscope?.y,
      gyroscopeZ: _lastGyroscope?.z,
      magnetometerX: _lastMagnetometer?.x,
      magnetometerY: _lastMagnetometer?.y,
      magnetometerZ: _lastMagnetometer?.z,
    );
  }

  /// Add sensor data to buffer
  void addToBuffer(SensorData data) {
    _sensorBuffer.add(data);
    if (_sensorBuffer.length > _maxBufferSize) {
      _sensorBuffer.removeAt(0);
    }
  }

  /// Get sensor buffer for analysis
  List<SensorData> getSensorBuffer() {
    return List.unmodifiable(_sensorBuffer);
  }

  /// Clear sensor buffer
  void clearBuffer() {
    _sensorBuffer.clear();
  }

  /// Analyze sensor data for movement detection
  MovementAnalysisResult analyzeMovement() {
    if (_sensorBuffer.isEmpty) {
      return MovementAnalysisResult(
        isMoving: false,
        confidence: 0.0,
        movementType: MovementType.unknown,
      );
    }

    // Calculate average accelerometer magnitude
    double totalMagnitude = 0;
    int validReadings = 0;

    for (var data in _sensorBuffer) {
      final magnitude = data.accelerometerMagnitude;
      if (magnitude != null) {
        totalMagnitude += magnitude;
        validReadings++;
      }
    }

    if (validReadings == 0) {
      return MovementAnalysisResult(
        isMoving: false,
        confidence: 0.0,
        movementType: MovementType.unknown,
      );
    }

    final avgMagnitude = totalMagnitude / validReadings;
    const double gravitySquared = 9.8 * 9.8;
    final deviation = (avgMagnitude - gravitySquared).abs();

    // Determine movement type based on deviation
    MovementType movementType;
    bool isMoving;
    double confidence;

    if (deviation < 1.0) {
      movementType = MovementType.stationary;
      isMoving = false;
      confidence = 0.9;
    } else if (deviation < 5.0) {
      movementType = MovementType.walking;
      isMoving = true;
      confidence = 0.7;
    } else if (deviation < 15.0) {
      movementType = MovementType.vehicle;
      isMoving = true;
      confidence = 0.8;
    } else {
      movementType = MovementType.erratic;
      isMoving = true;
      confidence = 0.5;
    }

    return MovementAnalysisResult(
      isMoving: isMoving,
      confidence: confidence,
      movementType: movementType,
      averageMagnitude: avgMagnitude,
      deviation: deviation,
    );
  }

  /// Get device security information
  Future<DeviceSecurityInfo> getDeviceSecurityInfo() async {
    if (_cachedSecurityInfo != null) {
      return _cachedSecurityInfo!;
    }

    final deviceInfo = DeviceInfoPlugin();

    String? deviceModel;
    String? osVersion;
    bool isEmulator = false;
    String? deviceId;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release}';
        deviceId = androidInfo.id;

        // Check if running on emulator
        isEmulator = !androidInfo.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceModel = iosInfo.model;
        osVersion = 'iOS ${iosInfo.systemVersion}';
        deviceId = iosInfo.identifierForVendor;

        // Check if running on simulator
        isEmulator = !iosInfo.isPhysicalDevice;
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }

    // Check for mock location (Android only)
    bool isMockLocationEnabled = false;
    if (Platform.isAndroid) {
      isMockLocationEnabled = await _checkMockLocationEnabled();
    }

    // Check for root/jailbreak
    bool isDeviceRooted = await _checkDeviceRooted();

    // Check for known mock location apps
    List<String> installedMockApps = await _checkInstalledMockApps();

    _cachedSecurityInfo = DeviceSecurityInfo(
      isMockLocationEnabled: isMockLocationEnabled,
      isDeviceRooted: isDeviceRooted,
      isEmulator: isEmulator,
      deviceModel: deviceModel,
      osVersion: osVersion,
      deviceId: deviceId,
      timezone: DateTime.now().timeZoneName,
      installedMockApps: installedMockApps,
    );

    return _cachedSecurityInfo!;
  }

  /// Refresh device security info (force re-check)
  Future<DeviceSecurityInfo> refreshDeviceSecurityInfo() async {
    _cachedSecurityInfo = null;
    return getDeviceSecurityInfo();
  }

  /// Check if mock location is enabled (simplified check)
  Future<bool> _checkMockLocationEnabled() async {
    // This would require native code implementation for accurate detection
    // For now, return false as placeholder
    // In production, use a native plugin or method channel
    return false;
  }

  /// Check if device is rooted/jailbroken (simplified check)
  Future<bool> _checkDeviceRooted() async {
    if (Platform.isAndroid) {
      // Check for common root indicators
      final rootPaths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
        '/su/bin/su',
      ];

      for (var path in rootPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
    }

    return false;
  }

  /// Check for installed mock location apps
  Future<List<String>> _checkInstalledMockApps() async {
    // List of known fake GPS app package names
    // In production, this would use PackageManager on Android
    final knownMockApps = [
      'com.lexa.fakegps',
      'com.fakegps.mock',
      'com.blogspot.newapphorizons.fakegps',
      'com.gsmartstudio.fakegps',
      'com.incorporateapps.fakegps.fre',
      'com.fakegps.mock.location',
      'ru.gavrikov.mocklocations',
      'com.theappninjas.fakegpsjoystick',
      'com.divi.fakeGPS',
      'com.lkr.fakelocation',
    ];

    // In a real implementation, you would check if these apps are installed
    // This requires platform-specific code
    return [];
  }
}

/// Result of movement analysis
class MovementAnalysisResult {
  final bool isMoving;
  final double confidence;
  final MovementType movementType;
  final double? averageMagnitude;
  final double? deviation;

  MovementAnalysisResult({
    required this.isMoving,
    required this.confidence,
    required this.movementType,
    this.averageMagnitude,
    this.deviation,
  });
}

/// Types of movement detected
enum MovementType {
  stationary,
  walking,
  vehicle,
  erratic,
  unknown,
}