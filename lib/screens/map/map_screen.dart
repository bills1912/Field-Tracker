// lib/screens/map/map_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:field_tracker/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../models/respondent.dart';
import '../../models/location_tracking.dart';
import '../respondent/add_respondent_screen.dart';

enum BaseMapType {
  openStreetMap,
  googleSatellite,
  googleHybrid,
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<Respondent> _respondents = [];
  List<LocationTracking> _enumeratorLocations = [];
  bool _isLoading = true;
  Position? _myPosition;
  String _viewMode = 'map'; // 'map' or 'list'
  BaseMapType _currentBaseMap = BaseMapType.openStreetMap;

  // Navigation state
  bool _isNavigating = false;
  Respondent? _navigationTarget;
  StreamSubscription<Position>? _positionSubscription;
  double? _distanceToTarget;
  double? _bearingToTarget;

  // Google Maps Tile URLs
  static const String _googleSatelliteUrl =
      'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  static const String _googleHybridUrl =
      'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
  static const String _openStreetMapUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    _loadMapData();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMapData() async {
    setState(() => _isLoading = true);

    try {
      final respondents = await ApiService.instance.getRespondents();
      final locations = await ApiService.instance.getLatestLocations();

      setState(() {
        _respondents = respondents;
        _enumeratorLocations = locations;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading map data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _myPosition = position);

      // Center map on user location
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        13,
      );
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  Color _getMarkerColor(RespondentStatus status) {
    switch (status) {
      case RespondentStatus.pending:
        return Colors.red;
      case RespondentStatus.in_progress:
        return Colors.orange;
      case RespondentStatus.completed:
        return Colors.green;
    }
  }

  String _getTileUrl() {
    switch (_currentBaseMap) {
      case BaseMapType.googleSatellite:
        return _googleSatelliteUrl;
      case BaseMapType.googleHybrid:
        return _googleHybridUrl;
      case BaseMapType.openStreetMap:
      default:
        return _openStreetMapUrl;
    }
  }

  String _getBaseMapName(BaseMapType type) {
    switch (type) {
      case BaseMapType.openStreetMap:
        return 'OpenStreetMap';
      case BaseMapType.googleSatellite:
        return 'Google Satellite';
      case BaseMapType.googleHybrid:
        return 'Google Hybrid';
    }
  }

  IconData _getBaseMapIcon(BaseMapType type) {
    switch (type) {
      case BaseMapType.openStreetMap:
        return Icons.map_outlined;
      case BaseMapType.googleSatellite:
        return Icons.satellite_alt;
      case BaseMapType.googleHybrid:
        return Icons.layers;
    }
  }

  void _showBaseMapSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers, color: Color(0xFF2196F3)),
                const SizedBox(width: 12),
                const Text(
                  'Select Base Map',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose your preferred map style',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
            ...BaseMapType.values.map((type) => _buildBaseMapOption(type)),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildBaseMapOption(BaseMapType type) {
    final isSelected = _currentBaseMap == type;

    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Color(0xFF2196F3), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          setState(() => _currentBaseMap = type);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2196F3).withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getBaseMapIcon(type),
                  size: 28,
                  color: isSelected ? const Color(0xFF2196F3) : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getBaseMapName(type),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF2196F3)
                            : const Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getBaseMapDescription(type),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF2196F3),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getBaseMapDescription(BaseMapType type) {
    switch (type) {
      case BaseMapType.openStreetMap:
        return 'Standard street map view';
      case BaseMapType.googleSatellite:
        return 'Satellite imagery from Google';
      case BaseMapType.googleHybrid:
        return 'Satellite with road labels';
    }
  }

  // ==================== NAVIGATION METHODS ====================

  /// Calculate distance between two points in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Calculate bearing between two points
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final double dLon = _toRadians(lon2 - lon1);
    final double y = sin(dLon) * cos(_toRadians(lat2));
    final double x = cos(_toRadians(lat1)) * sin(_toRadians(lat2)) -
        sin(_toRadians(lat1)) * cos(_toRadians(lat2)) * cos(dLon);
    return (_toDegrees(atan2(y, x)) + 360) % 360;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
  double _toDegrees(double radians) => radians * 180 / pi;

  /// Format distance for display
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

  /// Get direction text from bearing
  String _getDirectionText(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return 'N';
    if (bearing >= 22.5 && bearing < 67.5) return 'NE';
    if (bearing >= 67.5 && bearing < 112.5) return 'E';
    if (bearing >= 112.5 && bearing < 157.5) return 'SE';
    if (bearing >= 157.5 && bearing < 202.5) return 'S';
    if (bearing >= 202.5 && bearing < 247.5) return 'SW';
    if (bearing >= 247.5 && bearing < 292.5) return 'W';
    return 'NW';
  }

  /// Start in-app navigation to respondent
  void _startInAppNavigation(Respondent respondent) {
    setState(() {
      _isNavigating = true;
      _navigationTarget = respondent;
      _viewMode = 'map';
    });

    // Start listening to position updates
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((Position position) {
      setState(() {
        _myPosition = position;
        _distanceToTarget = _calculateDistance(
          position.latitude,
          position.longitude,
          respondent.latitude,
          respondent.longitude,
        );
        _bearingToTarget = _calculateBearing(
          position.latitude,
          position.longitude,
          respondent.latitude,
          respondent.longitude,
        );
      });

      // Check if arrived (within 10 meters)
      if (_distanceToTarget != null && _distanceToTarget! < 10) {
        _showArrivedDialog();
      }
    });

    // Center map to show both user and target
    _fitBoundsForNavigation(respondent);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navigating to ${respondent.name}'),
        backgroundColor: const Color(0xFF2196F3),
      ),
    );
  }

  /// Fit map bounds to show user and target
  void _fitBoundsForNavigation(Respondent respondent) {
    if (_myPosition == null) return;

    final bounds = LatLngBounds(
      LatLng(_myPosition!.latitude, _myPosition!.longitude),
      LatLng(respondent.latitude, respondent.longitude),
    );

    _mapController.fitBounds(
      bounds,
      options: const FitBoundsOptions(
        padding: EdgeInsets.all(50),
        maxZoom: 16,
      ),
    );
  }

  /// Stop in-app navigation
  void _stopNavigation() {
    _positionSubscription?.cancel();
    setState(() {
      _isNavigating = false;
      _navigationTarget = null;
      _distanceToTarget = null;
      _bearingToTarget = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigation stopped'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  /// Show dialog when arrived at destination
  void _showArrivedDialog() {
    _positionSubscription?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('Arrived!'),
          ],
        ),
        content: Text(
          'You have arrived at ${_navigationTarget?.name}\'s location.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopNavigation();
            },
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _stopNavigation();
              if (_navigationTarget != null) {
                _updateRespondentStatus(_navigationTarget!);
              }
            },
            child: const Text('Update Status'),
          ),
        ],
      ),
    );
  }

  /// Open Google Maps for navigation
  Future<void> _openGoogleMapsNavigation(Respondent respondent) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${respondent.latitude},${respondent.longitude}'
      '&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // Try alternative Google Maps URL
        final altUrl = Uri.parse(
          'geo:${respondent.latitude},${respondent.longitude}?q=${respondent.latitude},${respondent.longitude}(${Uri.encodeComponent(respondent.name)})',
        );
        
        if (await canLaunchUrl(altUrl)) {
          await launchUrl(altUrl, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Could not open Google Maps');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening Google Maps: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==================== BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final networkProvider = context.watch<NetworkProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Locations'),
        actions: [
          // Base Map Selector Button
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Change Base Map',
            onPressed: _showBaseMapSelector,
          ),
          IconButton(
            icon: Icon(_viewMode == 'map' ? Icons.list : Icons.map),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 'map' ? 'list' : 'map';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: networkProvider.isConnected ? _loadMapData : null,
          ),
          if (user?.role == UserRole.enumerator)
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddRespondentScreen(),
                  ),
                );
                if (result == true) {
                  _loadMapData(); // Refresh data after adding
                }
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _viewMode == 'map'
                  ? _buildMapView()
                  : _buildListView(),
          
          // Navigation Panel
          if (_isNavigating && _navigationTarget != null)
            _buildNavigationPanel(),
        ],
      ),
      floatingActionButton: _viewMode == 'map' && !_isNavigating
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Base Map Quick Toggle FAB
                FloatingActionButton(
                  heroTag: 'basemap',
                  mini: true,
                  backgroundColor: Colors.white,
                  child: Icon(
                    _getBaseMapIcon(_currentBaseMap),
                    color: const Color(0xFF2196F3),
                  ),
                  onPressed: _showBaseMapSelector,
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'location',
                  mini: true,
                  child: const Icon(Icons.my_location),
                  onPressed: _getCurrentLocation,
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'legend',
                  mini: true,
                  child: const Icon(Icons.info_outline),
                  onPressed: _showLegend,
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildNavigationPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.navigation,
                    color: Color(0xFF2196F3),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Navigating to',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        _navigationTarget?.name ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: _stopNavigation,
                ),
              ],
            ),
            const Divider(height: 24),
            // Distance and Direction
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Distance
                Column(
                  children: [
                    const Icon(Icons.straighten, color: Color(0xFF2196F3), size: 28),
                    const SizedBox(height: 4),
                    Text(
                      _distanceToTarget != null
                          ? _formatDistance(_distanceToTarget!)
                          : '-- m',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Distance',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                // Direction
                Column(
                  children: [
                    Transform.rotate(
                      angle: _bearingToTarget != null
                          ? _toRadians(_bearingToTarget!)
                          : 0,
                      child: const Icon(
                        Icons.navigation,
                        color: Color(0xFF4CAF50),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _bearingToTarget != null
                          ? _getDirectionText(_bearingToTarget!)
                          : '--',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Direction',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Open in Google Maps button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Open in Google Maps'),
                onPressed: () => _openGoogleMapsNavigation(_navigationTarget!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: _myPosition != null
                ? LatLng(_myPosition!.latitude, _myPosition!.longitude)
                : const LatLng(-6.2088, 106.8456),
            zoom: 13,
            maxZoom: 18,
            minZoom: 5,
          ),
          children: [
            TileLayer(
              urlTemplate: _getTileUrl(),
              userAgentPackageName: 'com.fieldtracker.app',
              maxZoom: 20,
              subdomains: _currentBaseMap == BaseMapType.openStreetMap
                  ? const ['a', 'b', 'c']
                  : const [],
            ),
            // Navigation line
            if (_isNavigating && _myPosition != null && _navigationTarget != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      LatLng(_myPosition!.latitude, _myPosition!.longitude),
                      LatLng(_navigationTarget!.latitude, _navigationTarget!.longitude),
                    ],
                    strokeWidth: 4,
                    color: const Color(0xFF2196F3),
                    isDotted: true,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // User's current location
                if (_myPosition != null)
                  Marker(
                    point:
                        LatLng(_myPosition!.latitude, _myPosition!.longitude),
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 24),
                    ),
                  ),

                // Respondents
                ..._respondents.map((respondent) {
                  final isNavigationTarget =
                      _navigationTarget?.id == respondent.id;
                  return Marker(
                    point: LatLng(respondent.latitude, respondent.longitude),
                    width: isNavigationTarget ? 50 : 40,
                    height: isNavigationTarget ? 50 : 40,
                    child: GestureDetector(
                      onTap: () => _showRespondentDetails(respondent),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getMarkerColor(respondent.status),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isNavigationTarget
                                ? const Color(0xFF2196F3)
                                : Colors.white,
                            width: isNavigationTarget ? 4 : 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: isNavigationTarget ? 28 : 20,
                        ),
                      ),
                    ),
                  );
                }),

                // Enumerator locations
                ..._enumeratorLocations.map((location) {
                  return Marker(
                    point: LatLng(location.latitude, location.longitude),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_pin,
                          color: Colors.white, size: 20),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
        // Current Base Map Indicator (only show when not navigating)
        if (!_isNavigating)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getBaseMapIcon(_currentBaseMap),
                    size: 16,
                    color: const Color(0xFF2196F3),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _getBaseMapName(_currentBaseMap),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _respondents.length,
      itemBuilder: (context, index) {
        final respondent = _respondents[index];
        return Card(
          child: InkWell(
            onTap: () => _showRespondentDetails(respondent),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getMarkerColor(respondent.status),
                    radius: 24,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          respondent.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Status: ${respondent.status.name.replaceAll('_', ' ').toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _getMarkerColor(respondent.status),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_myPosition != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatDistance(_calculateDistance(
                              _myPosition!.latitude,
                              _myPosition!.longitude,
                              respondent.latitude,
                              respondent.longitude,
                            )),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Navigate Button
                  IconButton(
                    icon: const Icon(Icons.navigation, color: Color(0xFF2196F3)),
                    tooltip: 'Navigate in App',
                    onPressed: () => _startInAppNavigation(respondent),
                  ),
                  // Google Maps Button
                  IconButton(
                    icon: const Icon(Icons.directions, color: Color(0xFF4CAF50)),
                    tooltip: 'Open in Google Maps',
                    onPressed: () => _openGoogleMapsNavigation(respondent),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRespondentDetails(Respondent respondent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getMarkerColor(respondent.status),
                      radius: 28,
                      child: const Icon(Icons.person, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            respondent.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getMarkerColor(respondent.status)
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              respondent.status.name
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                color: _getMarkerColor(respondent.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Info
                _buildInfoRow(Icons.phone, 'Phone', respondent.phone ?? 'N/A'),
                _buildInfoRow(Icons.home, 'Address', respondent.address ?? 'N/A'),
                _buildInfoRow(
                  Icons.location_on,
                  'Location',
                  '${respondent.latitude.toStringAsFixed(6)}, ${respondent.longitude.toStringAsFixed(6)}',
                ),
                if (_myPosition != null)
                  _buildInfoRow(
                    Icons.straighten,
                    'Distance',
                    _formatDistance(_calculateDistance(
                      _myPosition!.latitude,
                      _myPosition!.longitude,
                      respondent.latitude,
                      respondent.longitude,
                    )),
                  ),
                const SizedBox(height: 24),
                // Navigation Buttons
                const Text(
                  'Navigation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.navigation),
                        label: const Text('Navigate Here'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _startInAppNavigation(respondent);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.directions),
                        label: const Text('Google Maps'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _openGoogleMapsNavigation(respondent);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action Buttons
                const Text(
                  'Actions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Update Status'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _updateRespondentStatus(respondent);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateRespondentStatus(Respondent respondent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: RespondentStatus.values.map((status) {
            return RadioListTile<RespondentStatus>(
              title: Text(status.name.replaceAll('_', ' ').toUpperCase()),
              value: status,
              groupValue: respondent.status,
              onChanged: (value) async {
                Navigator.pop(context);

                try {
                  await ApiService.instance.updateRespondent(
                    respondent.id,
                    {'status': value!.name},
                  );

                  await _loadMapData();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Status updated successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLegend() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Legend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendItem(Colors.red, 'Pending'),
            _buildLegendItem(Colors.orange, 'In Progress'),
            _buildLegendItem(Colors.green, 'Completed'),
            _buildLegendItem(const Color(0xFF2196F3), 'Enumerator'),
            _buildLegendItem(Colors.blue, 'Your Location'),
            const Divider(height: 24),
            const Text(
              'Base Maps',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildLegendMapItem(Icons.map_outlined, 'OpenStreetMap'),
            _buildLegendMapItem(Icons.satellite_alt, 'Google Satellite'),
            _buildLegendMapItem(Icons.layers, 'Google Hybrid'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildLegendMapItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2196F3)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}