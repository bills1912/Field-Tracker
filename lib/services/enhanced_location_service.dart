import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import 'package:workmanager/workmanager.dart';
import '../models/location_tracking.dart';
import '../models/sensor_data.dart';
import '../models/location_fraud_result.dart';
import 'location_fraud_detection_service.dart';
import 'sensor_collector_service.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'dart:math';

/// Enhanced location service dengan integrasi fraud detection
class EnhancedLocationService {
  static EnhancedLocationService? _instance;
  static EnhancedLocationService get instance =>
      _instance ??= EnhancedLocationService._();

  EnhancedLocationService._();

  final Location _location = Location();
  final LocationFraudDetectionService _fraudService =
      LocationFraudDetectionService.instance;
  final SensorCollectorService _sensorService = SensorCollectorService.instance;

  bool _isTracking = false;
  Timer? _locationTimer;
  StreamSubscription<LocationData>? _locationSubscription;
  String? _currentUserId;

  // Callback untuk fraud detection result
  Function(LocationFraudResult)? onFraudDetected;
  Function(EnhancedLocationTracking)? onLocationTracked;

  // Cache lokasi terakhir
  EnhancedLocationTracking? _lastLocation;

  /// Start enhanced tracking dengan fraud detection
  Future<void> startTracking(
      String userId, {
        Function(LocationFraudResult)? onFraud,
        Function(EnhancedLocationTracking)? onLocation,
      }) async {
    if (_isTracking) {
      debugPrint('⚠️ Tracking already started');
      return;
    }

    try {
      _currentUserId = userId;
      onFraudDetected = onFraud;
      onLocationTracked = onLocation;

      debugPrint('🚀 Starting enhanced location tracking...');

      // Request location service
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('Location service must be enabled');
        }
      }

      // Request permission
      PermissionStatus permission = await _location.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission != PermissionStatus.granted) {
          throw Exception('Location permission is required');
        }
      }

      // Configure location settings
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 300000, // 5 minutes
        distanceFilter: 10, // 10 meters
      );

      // Enable background mode
      try {
        await _location.enableBackgroundMode(enable: true);
      } catch (e) {
        debugPrint('⚠️ Background mode not available: $e');
      }

      // Start sensor collection
      await _sensorService.startCollecting();

      // Track initial location
      await _trackLocationWithFraudCheck(userId);

      // Start periodic tracking
      _locationTimer = Timer.periodic(
        const Duration(minutes: 5),
            (timer) async {
          try {
            await _trackLocationWithFraudCheck(userId);
          } catch (e) {
            debugPrint('⚠️ Periodic tracking error: $e');
          }
        },
      );

      // Register background task
      try {
        await Workmanager().registerPeriodicTask(
          'enhanced_location_tracking_$userId',
          'enhancedLocationTrackingTask',
          frequency: const Duration(minutes: 15),
          inputData: {'userId': userId},
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
      } catch (e) {
        debugPrint('⚠️ Background task registration failed: $e');
      }

      _isTracking = true;
      debugPrint('✅ Enhanced location tracking started');
    } catch (e) {
      debugPrint('❌ Error starting enhanced tracking: $e');
      _cleanup();
      rethrow;
    }
  }

  /// Stop enhanced tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    debugPrint('🛑 Stopping enhanced location tracking...');

    _cleanup();

    // Stop sensor collection
    await _sensorService.stopCollecting();

    // Disable background mode
    try {
      await _location.enableBackgroundMode(enable: false);
    } catch (e) {
      debugPrint('⚠️ Error disabling background mode: $e');
    }

    // Cancel background task
    if (_currentUserId != null) {
      try {
        await Workmanager()
            .cancelByUniqueName('enhanced_location_tracking_$_currentUserId');
      } catch (e) {
        debugPrint('⚠️ Error canceling background task: $e');
      }
    }

    _isTracking = false;
    _currentUserId = null;

    debugPrint('✅ Enhanced location tracking stopped');
  }

  void _cleanup() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    onFraudDetected = null;
    onLocationTracked = null;
  }

  /// Track location with fraud detection
  Future<EnhancedLocationTracking?> _trackLocationWithFraudCheck(
      String userId,
      ) async {
    try {
      debugPrint('📍 Tracking location with fraud check...');

      // Get location
      final locationData = await _location.getLocation().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Location timeout'),
      );

      if (locationData.latitude == null || locationData.longitude == null) {
        debugPrint('⚠️ Invalid location data');
        return null;
      }

      // Get sensor data
      final sensorData = _sensorService.getCurrentSensorData();
      _sensorService.addToBuffer(sensorData);

      // Get device security info
      final securityInfo = await _sensorService.getDeviceSecurityInfo();

      // Create enhanced location tracking
      final enhancedLocation = EnhancedLocationTracking(
        userId: userId,
        latitude: locationData.latitude!,
        longitude: locationData.longitude!,
        altitude: locationData.altitude,
        timestamp: DateTime.now(),
        accuracy: locationData.accuracy,
        speed: locationData.speed,
        bearing: locationData.heading,
        sensorData: sensorData,
        securityInfo: securityInfo,
        locationProvider: 'fused',
      );

      // Perform fraud analysis
      final fraudResult = await _fraudService.analyzeLocation(
        location: enhancedLocation,
      );

      // Update location with fraud result
      final finalLocation = enhancedLocation.copyWith(
        trustScore: fraudResult.trustScore,
        isFlagged: fraudResult.isFraudulent,
      );

      // Notify callbacks
      onLocationTracked?.call(finalLocation);

      if (fraudResult.isFraudulent) {
        onFraudDetected?.call(fraudResult);
        debugPrint('🚨 FRAUD DETECTED: Trust=${fraudResult.trustScore}');
      }

      // Save to cache
      _lastLocation = finalLocation;

      // Send to API
      try {
        await _sendLocationToApi(finalLocation, fraudResult);
      } catch (e) {
        debugPrint('⚠️ API error, saving locally: $e');
        await _saveLocationLocally(finalLocation);
      }

      return finalLocation;
    } catch (e) {
      debugPrint('❌ Error tracking location: $e');
      return null;
    }
  }

  /// Send location to API with fraud result
  Future<void> _sendLocationToApi(
      EnhancedLocationTracking location,
      LocationFraudResult fraudResult,
      ) async {
    // Convert to basic location tracking for API
    final basicLocation = LocationTracking(
      userId: location.userId,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: location.timestamp,
      accuracy: location.accuracy,
      batteryLevel: location.batteryLevel,
      isSynced: true,
    );

    await ApiService.instance.createLocation(basicLocation);

    // Also send fraud result if flagged
    if (fraudResult.isFraudulent) {
      // TODO: Implement API endpoint for fraud reports
      debugPrint('📤 Fraud result would be sent to API');
    }
  }

  /// Save location locally for later sync
  Future<void> _saveLocationLocally(EnhancedLocationTracking location) async {
    final basicLocation = LocationTracking(
      userId: location.userId,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: location.timestamp,
      accuracy: location.accuracy,
      batteryLevel: location.batteryLevel,
      isSynced: false,
    );

    await StorageService.instance.savePendingLocation(basicLocation);
  }

  /// Get current location with fraud check (one-time)
  Future<(EnhancedLocationTracking?, LocationFraudResult?)>
  getCurrentLocationWithFraudCheck(String userId) async {
    try {
      // Get location
      final locationData = await _location.getLocation();

      if (locationData.latitude == null || locationData.longitude == null) {
        return (null, null);
      }

      // Get sensor and security data
      final sensorData = _sensorService.getCurrentSensorData();
      final securityInfo = await _sensorService.getDeviceSecurityInfo();

      // Create enhanced location
      final enhancedLocation = EnhancedLocationTracking(
        userId: userId,
        latitude: locationData.latitude!,
        longitude: locationData.longitude!,
        altitude: locationData.altitude,
        timestamp: DateTime.now(),
        accuracy: locationData.accuracy,
        speed: locationData.speed,
        bearing: locationData.heading,
        sensorData: sensorData,
        securityInfo: securityInfo,
      );

      // Analyze for fraud
      final fraudResult = await _fraudService.analyzeLocation(
        location: enhancedLocation,
      );

      final finalLocation = enhancedLocation.copyWith(
        trustScore: fraudResult.trustScore,
        isFlagged: fraudResult.isFraudulent,
      );

      return (finalLocation, fraudResult);
    } catch (e) {
      debugPrint('❌ Error getting location with fraud check: $e');
      return (null, null);
    }
  }

  /// Quick fraud check without full analysis
  Future<bool> quickFraudCheck() async {
    try {
      final securityInfo = await _sensorService.getDeviceSecurityInfo();

      // Immediate red flags
      if (securityInfo.isMockLocationEnabled) return true;
      if (securityInfo.isEmulator) return true;
      if (securityInfo.isDeviceRooted) return true;
      if (securityInfo.installedMockApps?.isNotEmpty ?? false) return true;

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Calculate distance between two points
  double calculateDistance(
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

  // Getters
  bool get isTracking => _isTracking;
  String? get currentUserId => _currentUserId;
  EnhancedLocationTracking? get lastLocation => _lastLocation;
}