import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import '../services/location_service.dart';
import '../services/enhanced_location_service.dart';
import '../services/api_service.dart';
import '../models/location_tracking.dart';
import '../models/location_fraud_result.dart';
import '../models/sensor_data.dart';

class LocationProvider with ChangeNotifier {
  bool _isTracking = false;
  LocationData? _currentLocation;
  List<LocationTracking> _locationHistory = [];
  bool _isLoading = false;
  String? _error;

  // Fraud detection properties
  LocationFraudResult? _lastFraudResult;
  List<LocationFraudResult> _fraudHistory = [];

  // 🔒 LOCKED: Fraud detection selalu enabled, tidak bisa dimatikan
  final bool _isFraudDetectionEnabled = true;

  // 🆕 Callback untuk notify FraudDetectionProvider
  Function(LocationFraudResult)? onFraudResultCallback;

  bool get isTracking => _isTracking;
  LocationData? get currentLocation => _currentLocation;
  List<LocationTracking> get locationHistory => _locationHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Fraud detection getters
  LocationFraudResult? get lastFraudResult => _lastFraudResult;
  List<LocationFraudResult> get fraudHistory => _fraudHistory;
  bool get isFraudDetectionEnabled => _isFraudDetectionEnabled;
  bool get hasRecentFraud => _lastFraudResult?.isFraudulent ?? false;

  /// 🆕 Set callback untuk notify external providers
  void setOnFraudResultCallback(Function(LocationFraudResult)? callback) {
    onFraudResultCallback = callback;
  }

  /// Start tracking with fraud detection (RECOMMENDED - AUTO CALLED)
  Future<void> startTrackingWithFraudDetection(String userId) async {
    if (_isTracking) {
      debugPrint('⚠️ Tracking already active');
      return;
    }

    try {
      _error = null;
      debugPrint('🚀 Starting tracking with fraud detection for user: $userId');

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

          // 🆕 Notify external callback (FraudDetectionProvider)
          onFraudResultCallback?.call(fraudResult);

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
      debugPrint('✅ Tracking with fraud detection started');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isTracking = false;
      debugPrint('❌ Failed to start tracking: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Start location tracking
  /// 🔒 MODIFIED: Selalu menggunakan fraud detection
  Future<void> startTracking(String userId) async {
    // 🔒 ALWAYS use fraud detection - cannot be disabled
    await startTrackingWithFraudDetection(userId);
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    try {
      debugPrint('🛑 Stopping location tracking...');

      // Stop enhanced location service
      await EnhancedLocationService.instance.stopTracking();

      // Also try to stop basic service just in case
      try {
        await LocationService.instance.stopTracking();
      } catch (_) {}

      _isTracking = false;
      debugPrint('✅ Location tracking stopped');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error stopping tracking: $e');
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

  /// Get current location with fraud check
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
        if (_fraudHistory.length > 50) {
          _fraudHistory.removeLast();
        }

        // 🆕 Notify external callback (FraudDetectionProvider)
        onFraudResultCallback?.call(fraudResult);

        debugPrint('📊 Fraud check completed:');
        debugPrint('   Trust Score: ${fraudResult.trustScore}');
        debugPrint('   Is Fraudulent: ${fraudResult.isFraudulent}');
        debugPrint('   Flags: ${fraudResult.flags.length}');
      }

      notifyListeners();
      return (_currentLocation, fraudResult);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return (null, null);
    }
  }

  /// Quick fraud check (without full tracking)
  Future<bool> quickFraudCheck() async {
    try {
      return await EnhancedLocationService.instance.quickFraudCheck();
    } catch (e) {
      debugPrint('Error in quick fraud check: $e');
      return false;
    }
  }

  /// 🔒 LOCKED: Fraud detection tidak bisa dimatikan
  /// Method ini dipertahankan untuk backward compatibility, tapi tidak berpengaruh
  void setFraudDetectionEnabled(bool enabled) {
    // 🔒 LOCKED: Fraud detection selalu aktif untuk mencegah kecurangan
    debugPrint('ℹ️ Fraud detection is always enabled and cannot be disabled');
    // Tidak ada perubahan state, fraud detection tetap aktif
    notifyListeners();
  }

  /// Clear fraud history
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
        EnhancedLocationService.instance.isTracking;
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