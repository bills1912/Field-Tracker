import 'dart:async';
import 'package:location/location.dart';
import 'package:workmanager/workmanager.dart';
import '../models/location_tracking.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'dart:math';

/// Background location tracking dispatcher
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final userId = inputData?['userId'] as String?;
      if (userId != null) {
        await LocationService.instance.trackLocation(userId);
      }
      return Future.value(true);
    } catch (e) {
      print('Background location error: $e');
      return Future.value(false);
    }
  });
}

/// Location Service using 'location' package
class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();

  LocationService._();

  final Location _location = Location();

  bool _isTracking = false;
  Timer? _locationTimer;
  StreamSubscription<LocationData>? _locationSubscription;
  String? _currentUserId;

  /// Check if location service is enabled
  Future<bool> isLocationServiceEnabled() async {
    return await _location.serviceEnabled();
  }

  /// Request to enable location service
  Future<bool> requestLocationService() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }
    return true;
  }

  /// Check location permission
  Future<PermissionStatus> checkPermission() async {
    return await _location.hasPermission();
  }

  /// Request location permission with better error handling
  Future<PermissionStatus> requestPermission() async {
    try {
      PermissionStatus permission = await _location.hasPermission();

      print('📍 Current permission status: $permission');

      if (permission == PermissionStatus.denied) {
        print('🔐 Requesting location permission...');
        permission = await _location.requestPermission();
        print('📍 Permission after request: $permission');
      }

      // Throw specific errors for better handling
      if (permission == PermissionStatus.deniedForever) {
        throw Exception('PERMISSION_DENIED_FOREVER');
      }

      if (permission == PermissionStatus.denied) {
        throw Exception('PERMISSION_DENIED');
      }

      return permission;
    } catch (e) {
      print('❌ Permission request error: $e');
      rethrow;
    }
  }

  /// Initialize location settings
  Future<void> initializeSettings() async {
    try {
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 300000, // 5 minutes in milliseconds
        distanceFilter: 10, // 10 meters
      );

      // Enable background mode
      await _location.enableBackgroundMode(enable: true);
      print('✅ Location settings initialized');
    } catch (e) {
      print('⚠️ Error initializing settings: $e');
      // Continue even if background mode fails
    }
  }

  /// Get current location once
  Future<LocationData?> getCurrentLocation() async {
    try {
      // Check service
      final serviceEnabled = await requestLocationService();
      if (!serviceEnabled) {
        throw Exception('Location service is disabled');
      }

      // Check permission
      final permission = await requestPermission();
      if (permission != PermissionStatus.granted) {
        throw Exception('Location permission not granted');
      }

      // Get location
      return await _location.getLocation();
    } catch (e) {
      print('Error getting current location: $e');
      rethrow;
    }
  }

  /// Start continuous location tracking with improved error handling
  Future<void> startTracking(String userId) async {
    if (_isTracking) {
      print('⚠️ Location tracking already started');
      return;
    }

    try {
      _currentUserId = userId;

      print('🚀 Starting location tracking for user: $userId');

      // Step 1: Check and request service
      print('1️⃣ Checking location service...');
      final serviceEnabled = await requestLocationService();
      if (!serviceEnabled) {
        throw Exception('Location service must be enabled. Please enable GPS in your device settings.');
      }
      print('✅ Location service enabled');

      // Step 2: Check and request permission
      print('2️⃣ Checking location permission...');
      final permission = await requestPermission();
      if (permission != PermissionStatus.granted) {
        throw Exception('Location permission must be granted. Please allow location access in app settings.');
      }
      print('✅ Location permission granted');

      // Step 3: Initialize settings
      print('3️⃣ Initializing location settings...');
      await initializeSettings();
      print('✅ Settings initialized');

      // Step 4: Track immediately
      print('4️⃣ Getting initial location...');
      await trackLocation(userId);
      print('✅ Initial location tracked');

      // Step 5: Start periodic timer (every 5 minutes)
      print('5️⃣ Starting periodic tracking...');
      _locationTimer = Timer.periodic(
        const Duration(minutes: 5),
            (timer) async {
          try {
            await trackLocation(userId);
          } catch (e) {
            print('⚠️ Periodic tracking error: $e');
          }
        },
      );

      // Step 6: Register background task with WorkManager
      print('6️⃣ Registering background task...');
      try {
        await Workmanager().registerPeriodicTask(
          'location_tracking_$userId',
          'locationTrackingTask',
          frequency: const Duration(minutes: 15), // Minimum for WorkManager
          inputData: {'userId': userId},
          constraints: Constraints(
            networkType: NetworkType.notRequired,
          ),
        );
        print('✅ Background task registered');
      } catch (e) {
        print('⚠️ Background task registration failed: $e');
        // Continue without background task
      }

      _isTracking = true;
      print('✅ Location tracking started successfully!');
    } catch (e) {
      print('❌ Error starting location tracking: $e');
      // Clean up on error
      _locationTimer?.cancel();
      _locationTimer = null;
      _currentUserId = null;
      _isTracking = false;
      rethrow;
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    try {
      print('🛑 Stopping location tracking...');

      // Cancel timer
      _locationTimer?.cancel();
      _locationTimer = null;

      // Cancel location subscription
      await _locationSubscription?.cancel();
      _locationSubscription = null;

      // Disable background mode
      try {
        await _location.enableBackgroundMode(enable: false);
      } catch (e) {
        print('⚠️ Error disabling background mode: $e');
      }

      // Cancel WorkManager tasks
      if (_currentUserId != null) {
        try {
          await Workmanager().cancelByUniqueName('location_tracking_$_currentUserId');
        } catch (e) {
          print('⚠️ Error canceling WorkManager task: $e');
        }
      }

      _isTracking = false;
      _currentUserId = null;

      print('✅ Location tracking stopped');
    } catch (e) {
      print('❌ Error stopping location tracking: $e');
    }
  }

  /// Track location once and save
  Future<void> trackLocation(String userId) async {
    try {
      print('📍 Tracking location for user: $userId');

      // Get current location with timeout
      final locationData = await _location.getLocation().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Location request timed out');
        },
      );

      if (locationData.latitude == null || locationData.longitude == null) {
        print('⚠️ Invalid location data');
        return;
      }

      // Create location tracking object
      final tracking = LocationTracking(
        userId: userId,
        latitude: locationData.latitude!,
        longitude: locationData.longitude!,
        timestamp: DateTime.now(),
        accuracy: locationData.accuracy,
        isSynced: false,
      );

      print('📌 Location: ${tracking.latitude}, ${tracking.longitude}');
      print('🎯 Accuracy: ${tracking.accuracy}m');

      // Try to send to API
      try {
        await ApiService.instance.createLocation(tracking);
        print('✅ Location sent to server');
      } catch (apiError) {
        // If API fails, save to local storage
        print('⚠️ API failed, saving locally: $apiError');
        await StorageService.instance.savePendingLocation(tracking);
        print('💾 Location saved locally');
      }
    } catch (e) {
      print('❌ Error tracking location: $e');
      // Don't rethrow - we want tracking to continue even if one update fails
    }
  }

  /// Start real-time location listening
  Future<void> startLocationListener(
      String userId,
      Function(LocationData) onLocationChanged,
      ) async {
    try {
      // Request permissions
      final serviceEnabled = await requestLocationService();
      if (!serviceEnabled) {
        throw Exception('Location service is required');
      }

      final permission = await requestPermission();
      if (permission != PermissionStatus.granted) {
        throw Exception('Location permission is required');
      }

      // Initialize settings
      await initializeSettings();

      // Listen to location changes
      _locationSubscription = _location.onLocationChanged.listen(
            (LocationData locationData) async {
          onLocationChanged(locationData);

          // Also save to database periodically
          if (locationData.latitude != null && locationData.longitude != null) {
            final tracking = LocationTracking(
              userId: userId,
              latitude: locationData.latitude!,
              longitude: locationData.longitude!,
              timestamp: DateTime.now(),
              accuracy: locationData.accuracy,
              isSynced: false,
            );

            try {
              await ApiService.instance.createLocation(tracking);
            } catch (e) {
              await StorageService.instance.savePendingLocation(tracking);
            }
          }
        },
        onError: (error) {
          print('Location listener error: $error');
        },
      );

      print('✅ Real-time location listener started');
    } catch (e) {
      print('❌ Error starting location listener: $e');
      rethrow;
    }
  }

  /// Stop real-time location listening
  Future<void> stopLocationListener() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    print('✅ Real-time location listener stopped');
  }

  /// Calculate distance between two points (in kilometers)
  double calculateDistance(
      double lat1, double lon1,
      double lat2, double lon2,
      ) {
    // Using Haversine formula
    const double earthRadius = 6371; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2));

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Check if currently tracking
  bool get isTracking => _isTracking;

  /// Get current tracking user ID
  String? get currentUserId => _currentUserId;
}