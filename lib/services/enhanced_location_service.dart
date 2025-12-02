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

/// Enhanced location service dengan integrasi fraud detection dan offline support
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

  // Cache lokasi terakhir (untuk offline mode)
  EnhancedLocationTracking? _lastLocation;
  LocationData? _lastRawLocation;

  // Stream controller untuk real-time updates
  final StreamController<EnhancedLocationTracking> _locationStreamController =
  StreamController<EnhancedLocationTracking>.broadcast();

  /// Stream untuk real-time location updates
  Stream<EnhancedLocationTracking> get locationStream => _locationStreamController.stream;

  /// Start enhanced tracking dengan fraud detection dan real-time updates
  /// UPDATED: Interval dari 5 menit ke 2 menit
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

      // Configure location settings for real-time tracking
      // UPDATED: Interval lebih cepat untuk real-time
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000, // 5 detik untuk real-time UI updates
        distanceFilter: 5, // 5 meters - lebih sensitif
      );

      // Enable background mode
      try {
        await _location.enableBackgroundMode(enable: true);
      } catch (e) {
        debugPrint('⚠️ Background mode not available: $e');
      }

      // Start sensor collection
      await _sensorService.startCollecting();

      // Start real-time location listener
      await _startRealTimeListener(userId);

      // Track initial location
      await _trackLocationWithFraudCheck(userId);

      // Start periodic tracking - UPDATED: 2 menit (sebelumnya 5 menit)
      _locationTimer = Timer.periodic(
        const Duration(minutes: 2), // CHANGED: dari 5 menit ke 2 menit
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

  /// Start real-time location listener
  Future<void> _startRealTimeListener(String userId) async {
    await _locationSubscription?.cancel();

    _locationSubscription = _location.onLocationChanged.listen(
          (LocationData locationData) async {
        debugPrint('📍 Real-time update: ${locationData.latitude}, ${locationData.longitude}');

        // Cache raw location
        _lastRawLocation = locationData;

        if (locationData.latitude == null || locationData.longitude == null) {
          return;
        }

        // Get sensor data
        final sensorData = _sensorService.getCurrentSensorData();

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
          locationProvider: 'fused',
        );

        // Cache enhanced location
        _lastLocation = enhancedLocation;

        // Notify callback
        onLocationTracked?.call(enhancedLocation);

        // Broadcast to stream
        if (!_locationStreamController.isClosed) {
          _locationStreamController.add(enhancedLocation);
        }

        // Save location (works offline)
        await _saveLocationOfflineFirst(enhancedLocation);
      },
      onError: (error) {
        debugPrint('❌ Real-time listener error: $error');
      },
      cancelOnError: false,
    );
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

      // Get location with timeout, fallback to cache
      LocationData locationData;
      try {
        locationData = await _location.getLocation().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            if (_lastRawLocation != null) {
              debugPrint('⚠️ Timeout - using cached location');
              return _lastRawLocation!;
            }
            throw TimeoutException('Location timeout');
          },
        );
      } catch (e) {
        if (_lastRawLocation != null) {
          locationData = _lastRawLocation!;
        } else {
          debugPrint('❌ Cannot get location: $e');
          return null;
        }
      }

      if (locationData.latitude == null || locationData.longitude == null) {
        debugPrint('⚠️ Invalid location data');
        return _lastLocation; // Return cached
      }

      // Cache raw location
      _lastRawLocation = locationData;

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

      // Broadcast to stream
      if (!_locationStreamController.isClosed) {
        _locationStreamController.add(finalLocation);
      }

      // Save location (offline first)
      await _saveLocationOfflineFirst(finalLocation, fraudResult: fraudResult);

      return finalLocation;
    } catch (e) {
      debugPrint('❌ Error tracking location: $e');
      return _lastLocation; // Return cached on error
    }
  }

  /// Save location - OFFLINE FIRST approach
  Future<void> _saveLocationOfflineFirst(
      EnhancedLocationTracking location, {
        LocationFraudResult? fraudResult,
      }) async {
    // Always save to local storage first (offline support)
    final basicLocation = LocationTracking(
      userId: location.userId,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: location.timestamp,
      accuracy: location.accuracy,
      batteryLevel: location.batteryLevel,
      isSynced: false,
    );

    // Save locally first
    await StorageService.instance.savePendingLocation(basicLocation);
    debugPrint('💾 Location saved locally');

    // Then try to send to API
    try {
      await ApiService.instance.createLocation(basicLocation);
      debugPrint('✅ Location synced to server');
      // Mark as synced by removing from pending (optional optimization)
    } catch (e) {
      debugPrint('⚠️ Will sync later when online: $e');
      // Location already saved locally, will sync later
    }
  }

  /// Get current location with fraud check (one-time)
  Future<(EnhancedLocationTracking?, LocationFraudResult?)>
  getCurrentLocationWithFraudCheck(String userId) async {
    try {
      // Try to get location, fallback to cache
      LocationData? locationData;
      try {
        locationData = await _location.getLocation().timeout(
          const Duration(seconds: 15),
        );
      } catch (e) {
        locationData = _lastRawLocation;
      }

      if (locationData?.latitude == null || locationData?.longitude == null) {
        // Return cached if available
        if (_lastLocation != null) {
          return (_lastLocation, null);
        }
        return (null, null);
      }

      // Cache raw location
      _lastRawLocation = locationData;

      // Get sensor and security data
      final sensorData = _sensorService.getCurrentSensorData();
      final securityInfo = await _sensorService.getDeviceSecurityInfo();

      // Create enhanced location
      final enhancedLocation = EnhancedLocationTracking(
        userId: userId,
        latitude: locationData!.latitude!,
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

      // Cache
      _lastLocation = finalLocation;

      return (finalLocation, fraudResult);
    } catch (e) {
      debugPrint('❌ Error getting location with fraud check: $e');
      // Return cached
      return (_lastLocation, null);
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
  LocationData? get lastRawLocation => _lastRawLocation;

  /// Dispose resources
  void dispose() {
    _cleanup();
    _locationStreamController.close();
  }
}