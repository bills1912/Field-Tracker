import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import '../services/location_service.dart';
import '../services/enhanced_location_service.dart'; // 🆕 NEW
import '../services/api_service.dart';
import '../models/location_tracking.dart';
import '../models/location_fraud_result.dart'; // 🆕 NEW
import '../models/sensor_data.dart'; // 🆕 NEW

class LocationProvider with ChangeNotifier {
  bool _isTracking = false;
  LocationData? _currentLocation;
  List<LocationTracking> _locationHistory = [];
  bool _isLoading = false;
  String? _error;

  // 🆕 NEW: Fraud detection properties
  LocationFraudResult? _lastFraudResult;
  List<LocationFraudResult> _fraudHistory = [];
  bool _isFraudDetectionEnabled = true;

  bool get isTracking => _isTracking;
  LocationData? get currentLocation => _currentLocation;
  List<LocationTracking> get locationHistory => _locationHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // 🆕 NEW: Fraud detection getters
  LocationFraudResult? get lastFraudResult => _lastFraudResult;
  List<LocationFraudResult> get fraudHistory => _fraudHistory;
  bool get isFraudDetectionEnabled => _isFraudDetectionEnabled;
  bool get hasRecentFraud => _lastFraudResult?.isFraudulent ?? false;

  /// 🆕 NEW: Start tracking with fraud detection
  Future<void> startTrackingWithFraudDetection(String userId) async {
    try {
      _error = null;

      // Use enhanced location service with fraud detection
      await EnhancedLocationService.instance.startTracking(
        userId,
        // Callback when fraud is detected
        onFraud: (fraudResult) {
          _lastFraudResult = fraudResult;
          _fraudHistory.insert(0, fraudResult);
          if (_fraudHistory.length > 50) {
            _fraudHistory.removeLast();
          }

          debugPrint('🚨 FRAUD DETECTED in LocationProvider');
          debugPrint('   Trust Score: ${fraudResult.trustScore}');
          debugPrint('   Flags: ${fraudResult.flags.length}');

          notifyListeners();
        },
        // Callback for each location update
        onLocation: (enhancedLocation) {
          _currentLocation = LocationData.fromMap({
            'latitude': enhancedLocation.latitude,
            'longitude': enhancedLocation.longitude,
            'accuracy': enhancedLocation.accuracy,
            'altitude': enhancedLocation.altitude,
            'speed': enhancedLocation.speed,
            'heading': enhancedLocation.bearing,
            'time': enhancedLocation.timestamp.millisecondsSinceEpoch.toDouble(),
          });

          notifyListeners();
        },
      );

      _isTracking = true;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isTracking = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Start location tracking (original method - still works)
  Future<void> startTracking(String userId) async {
    try {
      _error = null;

      // 🆕 UPDATED: Use enhanced tracking if fraud detection is enabled
      if (_isFraudDetectionEnabled) {
        await startTrackingWithFraudDetection(userId);
        return;
      }

      // Original tracking without fraud detection
      await LocationService.instance.startTracking(userId);
      _isTracking = true;

      // Get initial location
      await updateCurrentLocation();

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isTracking = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    try {
      // 🆕 UPDATED: Stop enhanced location service if enabled
      if (_isFraudDetectionEnabled) {
        await EnhancedLocationService.instance.stopTracking();
      } else {
        await LocationService.instance.stopTracking();
      }

      _isTracking = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Update current location
  Future<void> updateCurrentLocation() async {
    try {
      _currentLocation = await LocationService.instance.getCurrentLocation();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 🆕 NEW: Get current location with fraud check
  Future<(LocationData?, LocationFraudResult?)> getCurrentLocationWithFraudCheck(
      String userId,
      ) async {
    try {
      final (enhancedLocation, fraudResult) =
      await EnhancedLocationService.instance.getCurrentLocationWithFraudCheck(userId);

      if (enhancedLocation != null) {
        _currentLocation = LocationData.fromMap({
          'latitude': enhancedLocation.latitude,
          'longitude': enhancedLocation.longitude,
          'accuracy': enhancedLocation.accuracy,
          'altitude': enhancedLocation.altitude,
          'speed': enhancedLocation.speed,
          'heading': enhancedLocation.bearing,
          'time': enhancedLocation.timestamp.millisecondsSinceEpoch.toDouble(),
        });
      }

      if (fraudResult != null) {
        _lastFraudResult = fraudResult;
        _fraudHistory.insert(0, fraudResult);
      }

      notifyListeners();
      return (_currentLocation, fraudResult);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return (null, null);
    }
  }

  /// 🆕 NEW: Quick fraud check (without full tracking)
  Future<bool> quickFraudCheck() async {
    try {
      return await EnhancedLocationService.instance.quickFraudCheck();
    } catch (e) {
      debugPrint('Error in quick fraud check: $e');
      return false;
    }
  }

  /// 🆕 NEW: Toggle fraud detection
  void setFraudDetectionEnabled(bool enabled) {
    _isFraudDetectionEnabled = enabled;
    notifyListeners();
  }

  /// 🆕 NEW: Clear fraud history
  void clearFraudHistory() {
    _fraudHistory.clear();
    _lastFraudResult = null;
    notifyListeners();
  }

  /// Start real-time location updates
  Future<void> startLocationListener(String userId) async {
    try {
      await LocationService.instance.startLocationListener(
        userId,
            (locationData) {
          _currentLocation = locationData;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Stop real-time location updates
  Future<void> stopLocationListener() async {
    await LocationService.instance.stopLocationListener();
    notifyListeners();
  }

  /// Load location history
  Future<void> loadLocationHistory() async {
    _isLoading = true;
    notifyListeners();

    try {
      _locationHistory = await ApiService.instance.getLatestLocations();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check tracking status
  void checkTrackingStatus() {
    _isTracking = LocationService.instance.isTracking ||
        EnhancedLocationService.instance.isTracking; // 🆕 UPDATED
    notifyListeners();
  }

  /// Calculate distance to a point
  double? calculateDistanceTo(double targetLat, double targetLon) {
    if (_currentLocation?.latitude == null || _currentLocation?.longitude == null) {
      return null;
    }

    return LocationService.instance.calculateDistance(
      _currentLocation!.latitude!,
      _currentLocation!.longitude!,
      targetLat,
      targetLon,
    );
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}