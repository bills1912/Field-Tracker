import 'dart:async';
import 'package:location/location.dart';
// import 'package:battery_plus/battery_plus.dart';
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
  // final Battery _battery = Battery();
  
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

  /// Request location permission
  Future<PermissionStatus> requestPermission() async {
    PermissionStatus permission = await _location.hasPermission();
    
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
    }
    
    return permission;
  }

  /// Initialize location settings
  Future<void> initializeSettings() async {
    await _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 300000, // 5 minutes in milliseconds
      distanceFilter: 10, // 10 meters
    );
    
    // Enable background mode
    await _location.enableBackgroundMode(enable: true);
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
      if (permission == PermissionStatus.denied || 
          permission == PermissionStatus.deniedForever) {
        throw Exception('Location permission denied');
      }

      // Get location
      return await _location.getLocation();
    } catch (e) {
      print('Error getting current location: $e');
      rethrow;
    }
  }

  /// Start continuous location tracking
  Future<void> startTracking(String userId) async {
    if (_isTracking) {
      print('Location tracking already started');
      return;
    }

    try {
      _currentUserId = userId;

      // Check and request permissions
      final serviceEnabled = await requestLocationService();
      if (!serviceEnabled) {
        throw Exception('Location service is required');
      }

      final permission = await requestPermission();
      if (permission == PermissionStatus.denied || 
          permission == PermissionStatus.deniedForever) {
        throw Exception('Location permission is required');
      }

      // Initialize settings
      await initializeSettings();

      // Track immediately
      await trackLocation(userId);

      // Start periodic timer (every 5 minutes)
      _locationTimer = Timer.periodic(
        const Duration(minutes: 5),
        (timer) async {
          await trackLocation(userId);
        },
      );

      // Register background task with WorkManager
      await Workmanager().registerPeriodicTask(
        'location_tracking_$userId',
        'locationTrackingTask',
        frequency: const Duration(minutes: 15), // Minimum for WorkManager
        inputData: {'userId': userId},
        constraints: Constraints(
          networkType: NetworkType.not_required,
        ),
      );

      _isTracking = true;
      print('✅ Location tracking started for user: $userId');
    } catch (e) {
      print('❌ Error starting location tracking: $e');
      rethrow;
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    try {
      // Cancel timer
      _locationTimer?.cancel();
      _locationTimer = null;

      // Cancel location subscription
      await _locationSubscription?.cancel();
      _locationSubscription = null;

      // Disable background mode
      await _location.enableBackgroundMode(enable: false);

      // Cancel WorkManager tasks
      if (_currentUserId != null) {
        await Workmanager().cancelByUniqueName('location_tracking_$_currentUserId');
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

      // Get current location
      final locationData = await _location.getLocation();
      
      if (locationData.latitude == null || locationData.longitude == null) {
        print('⚠️ Invalid location data');
        return;
      }

      // Get battery level
      // final batteryLevel = await _battery.batteryLevel;

      // Create location tracking object
      final tracking = LocationTracking(
        userId: userId,
        latitude: locationData.latitude!,
        longitude: locationData.longitude!,
        timestamp: DateTime.now(),
        accuracy: locationData.accuracy,
        // batteryLevel: batteryLevel,
        isSynced: false,
      );

      print('📌 Location: ${tracking.latitude}, ${tracking.longitude}');
      print('🎯 Accuracy: ${tracking.accuracy}m');
      print('🔋 Battery: ${tracking.batteryLevel}%');

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
      if (permission == PermissionStatus.denied || 
          permission == PermissionStatus.deniedForever) {
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
            // final batteryLevel = await _battery.batteryLevel;
            
            final tracking = LocationTracking(
              userId: userId,
              latitude: locationData.latitude!,
              longitude: locationData.longitude!,
              timestamp: DateTime.now(),
              accuracy: locationData.accuracy,
              // batteryLevel: batteryLevel,
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