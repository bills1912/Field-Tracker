import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
// import 'package:battery_plus/battery_plus.dart';
import '../models/location_tracking.dart';
import 'storage_service.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await BackgroundLocationService.instance.trackLocation();
      return Future.value(true);
    } catch (e) {
      print('Background location error: $e');
      return Future.value(false);
    }
  });
}

class BackgroundLocationService {
  static BackgroundLocationService? _instance;
  static BackgroundLocationService get instance => _instance ??= BackgroundLocationService._();
  
  BackgroundLocationService._();

  bool _isTracking = false;
  Timer? _locationTimer;
  // final Battery _battery = Battery();

  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  Future<bool> requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> startTracking(String userId) async {
    if (_isTracking) return;

    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    _isTracking = true;

    // Register periodic task (every 15 minutes - minimum for WorkManager)
    await Workmanager().registerPeriodicTask(
      'location_tracking',
      'location_tracking',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
      ),
    );

    // Use Timer for more frequent updates (every 5 minutes)
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await trackLocation();
    });
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    _locationTimer?.cancel();
    await Workmanager().cancelByUniqueName('location_tracking');
  }

  Future<void> trackLocation() async {
    try {
      final user = await StorageService.instance.getUser();
      if (user == null) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // final batteryLevel = await _battery.batteryLevel;

      final locationTracking = LocationTracking(
        userId: user.id,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        accuracy: position.accuracy,
        // batteryLevel: batteryLevel,
        isSynced: false,
      );

      // Try to send to API
      try {
        await ApiService.instance.createLocation(locationTracking);
      } catch (e) {
        // Save locally if API fails
        await StorageService.instance.savePendingLocation(locationTracking);
      }
    } catch (e) {
      print('Location tracking error: $e');
    }
  }

  bool get isTracking => _isTracking;
}