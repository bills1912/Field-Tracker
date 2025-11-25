import 'package:flutter/foundation.dart';
import 'package:location/location.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../models/location_tracking.dart';

class LocationProvider with ChangeNotifier {
  bool _isTracking = false;
  LocationData? _currentLocation;
  List<LocationTracking> _locationHistory = [];
  bool _isLoading = false;
  String? _error;

  bool get isTracking => _isTracking;
  LocationData? get currentLocation => _currentLocation;
  List<LocationTracking> get locationHistory => _locationHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Start location tracking
  Future<void> startTracking(String userId) async {
    try {
      _error = null;
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
      await LocationService.instance.stopTracking();
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
    _isTracking = LocationService.instance.isTracking;
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