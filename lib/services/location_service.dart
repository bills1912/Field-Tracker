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

/// Location Service using 'location' package with real-time updates
class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();

  LocationService._();

  final Location _location = Location();

  bool _isTracking = false;
  Timer? _locationTimer;
  StreamSubscription<LocationData>? _locationSubscription;
  String? _currentUserId;

  // Cache untuk lokasi terakhir (untuk offline mode)
  LocationData? _lastKnownLocation;

  // Stream controller untuk real-time updates
  final StreamController<LocationData> _locationStreamController =
  StreamController<LocationData>.broadcast();

  /// Stream untuk mendapatkan update lokasi real-time
  Stream<LocationData> get locationStream => _locationStreamController.stream;

  /// Lokasi terakhir yang diketahui
  LocationData? get lastKnownLocation => _lastKnownLocation;

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

  /// Initialize location settings for real-time tracking
  Future<void> initializeSettings() async {
    try {
      // UPDATED: Settings untuk real-time tracking
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000, // 5 detik untuk real-time updates
        distanceFilter: 5, // 5 meters - lebih sensitif
      );

      // Enable background mode
      await _location.enableBackgroundMode(enable: true);
      print('✅ Location settings initialized for real-time tracking');
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
        // Return cached location if service not available
        if (_lastKnownLocation != null) {
          print('📍 Returning cached location (service unavailable)');
          return _lastKnownLocation;
        }
        throw Exception('Location service is disabled');
      }

      // Check permission
      final permission = await requestPermission();
      if (permission != PermissionStatus.granted) {
        if (_lastKnownLocation != null) {
          print('📍 Returning cached location (permission denied)');
          return _lastKnownLocation;
        }
        throw Exception('Location permission not granted');
      }

      // Get location with timeout
      final locationData = await _location.getLocation().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (_lastKnownLocation != null) {
            print('📍 Timeout - returning cached location');
            return _lastKnownLocation!;
          }
          throw TimeoutException('Location request timed out');
        },
      );

      // Cache the location
      _lastKnownLocation = locationData;

      return locationData;
    } catch (e) {
      print('Error getting current location: $e');
      // Return cached if available
      if (_lastKnownLocation != null) {
        return _lastKnownLocation;
      }
      rethrow;
    }
  }

  /// Start continuous location tracking with real-time updates
  /// UPDATED: Interval dipercepat dari 5 menit ke 2 menit
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

      // Step 3: Initialize settings for real-time
      print('3️⃣ Initializing location settings...');
      await initializeSettings();
      print('✅ Settings initialized');

      // Step 4: Start real-time location listener
      print('4️⃣ Starting real-time location listener...');
      await _startRealTimeListener(userId);
      print('✅ Real-time listener started');

      // Step 5: Track immediately
      print('5️⃣ Getting initial location...');
      await trackLocation(userId);
      print('✅ Initial location tracked');

      // Step 6: Start periodic timer - UPDATED: 2 menit (sebelumnya 5 menit)
      print('6️⃣ Starting periodic tracking (every 2 minutes)...');
      _locationTimer = Timer.periodic(
        const Duration(minutes: 2), // CHANGED: dari 5 menit ke 2 menit
            (timer) async {
          try {
            await trackLocation(userId);
          } catch (e) {
            print('⚠️ Periodic tracking error: $e');
          }
        },
      );

      // Step 7: Register background task with WorkManager
      print('7️⃣ Registering background task...');
      try {
        await Workmanager().registerPeriodicTask(
          'location_tracking_$userId',
          'locationTrackingTask',
          frequency: const Duration(minutes: 15), // Minimum for WorkManager
          inputData: {'userId': userId},
          constraints: Constraints(
            networkType: NetworkType.notRequired, // Works offline
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
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _currentUserId = null;
      _isTracking = false;
      rethrow;
    }
  }

  /// Start real-time location listener
  Future<void> _startRealTimeListener(String userId) async {
    // Cancel existing subscription
    await _locationSubscription?.cancel();

    _locationSubscription = _location.onLocationChanged.listen(
          (LocationData locationData) async {
        print('📍 Real-time location update: ${locationData.latitude}, ${locationData.longitude}');

        // Cache the location
        _lastKnownLocation = locationData;

        // Broadcast to stream
        if (!_locationStreamController.isClosed) {
          _locationStreamController.add(locationData);
        }

        // Save to local storage for offline sync
        if (locationData.latitude != null && locationData.longitude != null) {
          final tracking = LocationTracking(
            userId: userId,
            latitude: locationData.latitude!,
            longitude: locationData.longitude!,
            timestamp: DateTime.now(),
            accuracy: locationData.accuracy,
            isSynced: false,
          );

          // Try API first, save locally if fails
          try {
            await ApiService.instance.createLocation(tracking);
            print('✅ Real-time location sent to server');
          } catch (e) {
            print('⚠️ Saving location locally for later sync: $e');
            await StorageService.instance.savePendingLocation(tracking);
          }
        }
      },
      onError: (error) {
        print('❌ Real-time location listener error: $error');
      },
      cancelOnError: false, // Don't cancel on error, keep trying
    );
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

  /// Track location once and save (works offline)
  Future<void> trackLocation(String userId) async {
    try {
      print('📍 Tracking location for user: $userId');

      // Get current location with timeout
      final locationData = await _location.getLocation().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          // Return cached location on timeout
          if (_lastKnownLocation != null) {
            print('⚠️ Timeout - using cached location');
            return _lastKnownLocation!;
          }
          throw TimeoutException('Location request timed out');
        },
      );

      if (locationData.latitude == null || locationData.longitude == null) {
        // Try cached location
        if (_lastKnownLocation != null) {
          print('⚠️ Invalid location data, using cache');
          await _saveLocation(userId, _lastKnownLocation!);
          return;
        }
        print('⚠️ Invalid location data and no cache available');
        return;
      }

      // Cache the location
      _lastKnownLocation = locationData;

      // Save the location
      await _saveLocation(userId, locationData);

    } catch (e) {
      print('❌ Error tracking location: $e');
      // Try to save cached location
      if (_lastKnownLocation != null) {
        await _saveLocation(userId, _lastKnownLocation!);
      }
    }
  }

  /// Save location to API or local storage
  Future<void> _saveLocation(String userId, LocationData locationData) async {
    if (locationData.latitude == null || locationData.longitude == null) return;

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
      // If API fails, save to local storage (OFFLINE MODE)
      print('⚠️ API failed, saving locally: $apiError');
      await StorageService.instance.savePendingLocation(tracking);
      print('💾 Location saved locally for later sync');
    }
  }

  /// Start real-time location listening (public method)
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
          // Cache the location
          _lastKnownLocation = locationData;

          // Notify callback
          onLocationChanged(locationData);

          // Broadcast to stream
          if (!_locationStreamController.isClosed) {
            _locationStreamController.add(locationData);
          }

          // Also save to database
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
        cancelOnError: false,
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

  /// Dispose resources
  void dispose() {
    _locationTimer?.cancel();
    _locationSubscription?.cancel();
    _locationStreamController.close();
  }
}