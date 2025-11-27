// lib/screens/map/survey_map_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:field_tracker/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/api_service.dart';
import '../../models/survey.dart';
import '../../models/respondent.dart';
import '../respondent/add_respondent_screen.dart';

enum BaseMapType {
  openStreetMap,
  googleSatellite,
  googleHybrid,
}

/// Survey-specific Map Screen with respondent filtering
class SurveyMapScreen extends StatefulWidget {
  final Survey survey;
  final RespondentStatus? statusFilter;

  const SurveyMapScreen({
    super.key,
    required this.survey,
    this.statusFilter,
  });

  @override
  State<SurveyMapScreen> createState() => _SurveyMapScreenState();
}

class _SurveyMapScreenState extends State<SurveyMapScreen> {
  final MapController _mapController = MapController();
  List<Respondent> _allRespondents = [];
  List<Respondent> _filteredRespondents = [];
  bool _isLoading = true;
  Position? _myPosition;
  String _viewMode = 'map'; // 'map' or 'list'
  BaseMapType _currentBaseMap = BaseMapType.openStreetMap;
  RespondentStatus? _currentFilter;

  // Navigation state
  bool _isNavigating = false;
  Respondent? _navigationTarget;
  StreamSubscription<Position>? _positionSubscription;
  double? _distanceToTarget;
  double? _bearingToTarget;

  // Tile URLs
  static const String _googleSatelliteUrl =
      'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  static const String _googleHybridUrl =
      'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
  static const String _openStreetMapUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.statusFilter;
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
      // Load respondents for this specific survey
      final respondents = await ApiService.instance.getRespondents(
        surveyId: widget.survey.id,
      );

      setState(() {
        _allRespondents = respondents;
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading respondents: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    if (_currentFilter == null) {
      _filteredRespondents = List.from(_allRespondents);
    } else {
      _filteredRespondents = _allRespondents
          .where((r) => r.status == _currentFilter)
          .toList();
    }
  }

  void _setFilter(RespondentStatus? filter) {
    setState(() {
      _currentFilter = filter;
      _applyFilter();
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _myPosition = position);

      // Center map based on respondents or user location
      // _centerMapOnContent();
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        13,
      );
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  void _centerMapOnContent() {
    if (_filteredRespondents.isNotEmpty) {
      // Calculate bounds to fit all respondents
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLon = double.infinity;
      double maxLon = double.negativeInfinity;

      for (var resp in _filteredRespondents) {
        minLat = min(minLat, resp.latitude);
        maxLat = max(maxLat, resp.latitude);
        minLon = min(minLon, resp.longitude);
        maxLon = max(maxLon, resp.longitude);
      }

      // Include user location if available
      if (_myPosition != null) {
        minLat = min(minLat, _myPosition!.latitude);
        maxLat = max(maxLat, _myPosition!.latitude);
        minLon = min(minLon, _myPosition!.longitude);
        maxLon = max(maxLon, _myPosition!.longitude);
      }

      // Add padding
      final latPadding = (maxLat - minLat) * 0.1;
      final lonPadding = (maxLon - minLon) * 0.1;

      _mapController.fitBounds(
        LatLngBounds(
          LatLng(minLat - latPadding, minLon - lonPadding),
          LatLng(maxLat + latPadding, maxLon + lonPadding),
        ),
        options: const FitBoundsOptions(
          padding: EdgeInsets.all(50),
          maxZoom: 16,
        ),
      );
    } else if (_myPosition != null) {
      _mapController.move(
        LatLng(_myPosition!.latitude, _myPosition!.longitude),
        13,
      );
    }
  }

  Color _getMarkerColor(RespondentStatus status) {
    switch (status) {
      case RespondentStatus.pending:
        return const Color(0xFFF44336);
      case RespondentStatus.in_progress:
        return const Color(0xFFFF9800);
      case RespondentStatus.completed:
        return const Color(0xFF4CAF50);
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

  String _getFilterLabel() {
    if (_currentFilter == null) return 'Semua';
    switch (_currentFilter!) {
      case RespondentStatus.pending:
        return 'Pending';
      case RespondentStatus.in_progress:
        return 'In Progress';
      case RespondentStatus.completed:
        return 'Completed';
    }
  }

  // ==================== NAVIGATION METHODS ====================

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
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

  double _calculateBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final double dLon = _toRadians(lon2 - lon1);
    final double y = sin(dLon) * cos(_toRadians(lat2));
    final double x = cos(_toRadians(lat1)) * sin(_toRadians(lat2)) -
        sin(_toRadians(lat1)) * cos(_toRadians(lat2)) * cos(dLon);
    return (_toDegrees(atan2(y, x)) + 360) % 360;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
  double _toDegrees(double radians) => radians * 180 / pi;

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

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

  void _startInAppNavigation(Respondent respondent) {
    setState(() {
      _isNavigating = true;
      _navigationTarget = respondent;
      _viewMode = 'map';
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
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

      if (_distanceToTarget != null && _distanceToTarget! < 10) {
        _showArrivedDialog();
      }
    });

    _fitBoundsForNavigation(respondent);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navigating to ${respondent.name}'),
        backgroundColor: const Color(0xFF2196F3),
      ),
    );
  }

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

  /// FIXED: Open Google Maps for navigation
  Future<void> _openGoogleMapsNavigation(Respondent respondent) async {
    final double lat = respondent.latitude;
    final double lng = respondent.longitude;
    final String label = Uri.encodeComponent(respondent.name);

    // Try different URL schemes
    final List<String> urlSchemes = [
      // Google Maps app with navigation mode
      'google.navigation:q=$lat,$lng&mode=d',
      // Google Maps app with location
      'geo:$lat,$lng?q=$lat,$lng($label)',
      // Google Maps web URL (fallback)
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      // Comgooglemaps scheme for iOS
      'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
    ];

    bool launched = false;

    for (String urlString in urlSchemes) {
      try {
        final Uri uri = Uri.parse(urlString);

        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          launched = true;
          break;
        }
      } catch (e) {
        print('Failed to launch $urlString: $e');
        continue;
      }
    }

    // If all schemes failed, try the web URL as last resort
    if (!launched) {
      try {
        final webUrl = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
        );

        await launchUrl(
          webUrl,
          mode: LaunchMode.externalApplication,
        );
        launched = true;
      } catch (e) {
        print('Failed to launch web URL: $e');
      }
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Tidak dapat membuka Google Maps. Pastikan aplikasi Google Maps terinstal.',
          ),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Copy Koordinat',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$lat, $lng'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Koordinat disalin ke clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ),
      );
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
            const Row(
              children: [
                Icon(Icons.layers, color: Color(0xFF2196F3)),
                SizedBox(width: 12),
                Text(
                  'Pilih Base Map',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...BaseMapType.values.map((type) => _buildBaseMapOption(type)),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2196F3).withOpacity(0.1)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getBaseMapIcon(type),
                  size: 24,
                  color:
                  isSelected ? const Color(0xFF2196F3) : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _getBaseMapName(type),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF2196F3)
                        : const Color(0xFF333333),
                  ),
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

  void _showFilterSheet() {
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
            const Row(
              children: [
                Icon(Icons.filter_list, color: Color(0xFF2196F3)),
                SizedBox(width: 12),
                Text(
                  'Filter Responden',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildFilterOption(null, 'Semua', _allRespondents.length),
            _buildFilterOption(
              RespondentStatus.pending,
              'Pending',
              _allRespondents
                  .where((r) => r.status == RespondentStatus.pending)
                  .length,
            ),
            _buildFilterOption(
              RespondentStatus.in_progress,
              'In Progress',
              _allRespondents
                  .where((r) => r.status == RespondentStatus.in_progress)
                  .length,
            ),
            _buildFilterOption(
              RespondentStatus.completed,
              'Completed',
              _allRespondents
                  .where((r) => r.status == RespondentStatus.completed)
                  .length,
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(RespondentStatus? status, String label, int count) {
    final isSelected = _currentFilter == status;
    final Color statusColor;

    if (status == null) {
      statusColor = const Color(0xFF2196F3);
    } else {
      statusColor = _getMarkerColor(status);
    }

    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: statusColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          _setFilter(status);
          Navigator.pop(context);
          _centerMapOnContent();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? statusColor : const Color(0xFF333333),
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: statusColor,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final networkProvider = context.watch<NetworkProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.survey.title,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              'Filter: ${_getFilterLabel()} (${_filteredRespondents.length})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Base Map',
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
          if (_isNavigating && _navigationTarget != null)
            _buildNavigationPanel(),
        ],
      ),
      floatingActionButton: _viewMode == 'map' && !_isNavigating
          ? Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'filter',
            mini: true,
            backgroundColor: _currentFilter != null
                ? _getMarkerColor(_currentFilter!)
                : Colors.white,
            onPressed: _showFilterSheet,
            child: Icon(
              Icons.filter_list,
              color: _currentFilter != null
                  ? Colors.white
                  : const Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'basemap',
            mini: true,
            backgroundColor: Colors.white,
            onPressed: _showBaseMapSelector,
            child: Icon(
              _getBaseMapIcon(_currentBaseMap),
              color: const Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'location',
            mini: true,
            backgroundColor: Colors.white,
            onPressed: _getCurrentLocation,
            child: const Icon(
              Icons.my_location,
              color: Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'fit',
            mini: true,
            backgroundColor: Colors.white,
            onPressed: _centerMapOnContent,
            child: const Icon(
              Icons.fit_screen,
              color: Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'legend',
            mini: true,
            backgroundColor: Colors.white,
            onPressed: _showLegend,
            child: const Icon(
              Icons.info_outline,
              color: Color(0xFF2196F3),
            ),
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
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.straighten,
                        color: Color(0xFF2196F3), size: 28),
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Buka di Google Maps'),
                onPressed: () =>
                    _openGoogleMapsNavigation(_navigationTarget!),
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
            ),
            // Navigation line
            if (_isNavigating &&
                _myPosition != null &&
                _navigationTarget != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      LatLng(_myPosition!.latitude, _myPosition!.longitude),
                      LatLng(_navigationTarget!.latitude,
                          _navigationTarget!.longitude),
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
                    point: LatLng(
                        _myPosition!.latitude, _myPosition!.longitude),
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
                // Filtered respondents
                ..._filteredRespondents.map((respondent) {
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
              ],
            ),
          ],
        ),
        // Info bar at top
        if (!_isNavigating)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    _getBaseMapIcon(_currentBaseMap),
                    size: 18,
                    color: const Color(0xFF2196F3),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_filteredRespondents.length} Responden (${_getFilterLabel()})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _currentFilter != null
                          ? _getMarkerColor(_currentFilter!).withOpacity(0.1)
                          : const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getFilterLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _currentFilter != null
                            ? _getMarkerColor(_currentFilter!)
                            : const Color(0xFF2196F3),
                      ),
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
    if (_filteredRespondents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Tidak ada responden dengan status ${_getFilterLabel()}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Tampilkan Semua'),
              onPressed: () => _setFilter(null),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredRespondents.length,
      itemBuilder: (context, index) {
        final respondent = _filteredRespondents[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getMarkerColor(respondent.status)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            respondent.status.name
                                .replaceAll('_', ' ')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: _getMarkerColor(respondent.status),
                              fontWeight: FontWeight.w600,
                            ),
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
                  IconButton(
                    icon: const Icon(Icons.navigation,
                        color: Color(0xFF2196F3)),
                    tooltip: 'Navigate in App',
                    onPressed: () => _startInAppNavigation(respondent),
                  ),
                  IconButton(
                    icon:
                    const Icon(Icons.directions, color: Color(0xFF4CAF50)),
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
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getMarkerColor(respondent.status),
                      radius: 28,
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 28),
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
                _buildInfoRow(
                    Icons.phone, 'Phone', respondent.phone ?? 'N/A'),
                _buildInfoRow(
                    Icons.home, 'Address', respondent.address ?? 'N/A'),
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
                        label: const Text('Navigate'),
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
              activeColor: _getMarkerColor(status),
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
            _buildLegendItem(
                const Color(0xFFF44336), 'Pending', Icons.location_on),
            _buildLegendItem(
                const Color(0xFFFF9800), 'In Progress', Icons.location_on),
            _buildLegendItem(
                const Color(0xFF4CAF50), 'Completed', Icons.location_on),
            _buildLegendItem(Colors.blue, 'Your Location', Icons.person),
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

  Widget _buildLegendItem(Color color, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}