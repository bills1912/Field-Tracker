// lib/screens/respondent/add_respondent_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../models/respondent.dart';
import '../../providers/auth_provider.dart';
import '../../providers/survey_provider.dart';
import '../../providers/fraud_detection_provider.dart'; // 🆕 NEW
import '../../services/api_service.dart';
import '../../widgets/fraud_detection_widgets.dart'; // 🆕 NEW
import '../../models/location_fraud_result.dart'; // 🆕 NEW
import 'dart:convert';
import 'package:flutter/services.dart'; // Untuk rootBundle
import 'package:latlong2/latlong.dart'; // Pastikan ini ada

enum BaseMapType {
  openStreetMap,
  googleSatellite,
  googleHybrid,
}

class AddRespondentScreen extends StatefulWidget {
  final String? geojsonPath;
  const AddRespondentScreen({super.key, this.geojsonPath,});

  @override
  State<AddRespondentScreen> createState() => _AddRespondentScreenState();
}

class _AddRespondentScreenState extends State<AddRespondentScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final _regionCodeController = TextEditingController();
  bool _isRegionCodeEditable = false;
  List<Map<String, dynamic>> _loadedPolygons = [];
  List<Polygon> _visualPolygons = [];

  // Form Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  // Location State
  Position? _currentPosition;
  LatLng? _selectedLocation;
  bool _isLoadingLocation = false;
  bool _isSubmitting = false;
  bool _useCurrentLocation = true;

  // Base Map
  BaseMapType _currentBaseMap = BaseMapType.openStreetMap;

  // 🆕 NEW: Fraud detection state
  LocationFraudResult? _fraudResult;
  bool _isValidatingLocation = false;
  bool _bypassFraudWarning = false;

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
    _getCurrentLocation();
    _loadGeoJsonData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _regionCodeController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = position;
        if (_useCurrentLocation) {
          _selectedLocation = latLng;
        }
      });

      if (_selectedLocation != null) {
        _mapController.move(_selectedLocation!, 17);
        _detectRegionFromLocation(_selectedLocation!);
      }

      // 🆕 NEW: Validate location after getting it
      await _validateCurrentLocation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  // 🆕 NEW: Validate location for fraud
  Future<void> _validateCurrentLocation() async {
    if (_selectedLocation == null) return;

    setState(() => _isValidatingLocation = true);

    try {
      final fraudProvider = context.read<FraudDetectionProvider>();
      final authProvider = context.read<AuthProvider>();

      // Quick check first
      final quickCheck = await fraudProvider.quickCheck(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
        _currentPosition?.accuracy,
      );

      if (quickCheck.isPotentiallyFraudulent) {
        // Show warning
        if (mounted) {
          _showFraudWarningDialog(quickCheck.reason, quickCheck.confidence);
        }
      }
    } catch (e) {
      debugPrint('Error validating location: $e');
    } finally {
      setState(() => _isValidatingLocation = false);
    }
  }

  // 🆕 NEW: Show fraud warning dialog
  void _showFraudWarningDialog(String reason, double confidence) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning, color: Colors.orange),
            ),
            const SizedBox(width: 12),
            const Text('Peringatan Lokasi'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confidence: ${(confidence * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pastikan Anda berada di lokasi yang benar dan tidak menggunakan fake GPS.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back from add respondent
            },
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _bypassFraudWarning = true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
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
                  color: isSelected ? const Color(0xFF2196F3) : Colors.grey[600],
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

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _useCurrentLocation = false;
      _bypassFraudWarning = false; // Reset bypass when location changes
    });
    _detectRegionFromLocation(point);

    // 🆕 NEW: Validate new location
    _validateCurrentLocation();
  }

  Future<void> _loadGeoJsonData() async {
    // Pastikan widget.geojsonPath dilempar dari screen sebelumnya
    if (widget.geojsonPath == null) return;

    try {
      final String data = await rootBundle.loadString(widget.geojsonPath!);
      final json = jsonDecode(data);

      if (json['features'] != null) {
        // List untuk Logika (Deteksi Otomatis)
        final List<Map<String, dynamic>> logicPolys = [];
        // List untuk Visual (Gambar di Peta)
        final List<Polygon> visualPolys = [];

        for (var feature in json['features']) {
          final geometry = feature['geometry'];
          final props = feature['properties'];
          if (geometry == null || props == null) continue;

          // Cek nama field kode wilayah (Default: ADM3_PCODE)
          final String pcode = props['ADM3_PCODE']?.toString()
              ?? props['region_code']?.toString()
              ?? '';

          if (pcode.isEmpty) continue;

          // Helper function agar tidak menulis ulang kode pembuatan polygon
          void addPolygon(List rawCoords) {
            final points = _parsePolygonCoordinates(rawCoords);

            // 1. Simpan untuk Logika Deteksi
            logicPolys.add({
              'code': pcode,
              'points': points,
            });

            // 2. Simpan untuk Visualisasi Peta
            visualPolys.add(
              Polygon(
                points: points,
                color: Colors.blue.withOpacity(0.15), // Warna isi (Transparan)
                borderColor: Colors.blue,             // Warna garis
                borderStrokeWidth: 2.0,
                isFilled: true,
              ),
            );
          }

          if (geometry['type'] == 'Polygon') {
            addPolygon(geometry['coordinates'][0]);
          } else if (geometry['type'] == 'MultiPolygon') {
            for (var poly in geometry['coordinates']) {
              addPolygon(poly[0]);
            }
          }
        }

        // Update State agar UI diperbarui
        setState(() {
          _loadedPolygons = logicPolys;
          _visualPolygons = visualPolys; // Pastikan variabel ini ada di class state Anda
        });

        debugPrint('✅ Loaded ${_loadedPolygons.length} polygons for logic & visual');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading autofill data: $e');
    }
  }

  List<LatLng> _parsePolygonCoordinates(List rawCoords) {
    return rawCoords.map<LatLng>((coord) {
      return LatLng(coord[1].toDouble(), coord[0].toDouble());
    }).toList();
  }

  /// Deteksi wilayah berdasarkan titik koordinat
  void _detectRegionFromLocation(LatLng point) {
    if (_loadedPolygons.isEmpty) return;
    // Jika user sedang edit manual, jangan timpa otomatis
    if (_isRegionCodeEditable && _regionCodeController.text.isNotEmpty) return;

    String foundCode = '';
    for (var poly in _loadedPolygons) {
      if (_isPointInPolygon(point, poly['points'])) {
        foundCode = poly['code'];
        break;
      }
    }

    if (foundCode.isNotEmpty) {
      setState(() => _regionCodeController.text = foundCode);

      // Optional: Beri notifikasi kecil
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Wilayah terdeteksi: $foundCode'),
        duration: const Duration(milliseconds: 800),
        backgroundColor: Colors.green,
      ));
    }
  }

  /// Algoritma Point in Polygon
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int j = 0; j < polygon.length - 1; j++) {
      if (_rayCastIntersect(point, polygon[j], polygon[j + 1])) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  bool _rayCastIntersect(LatLng point, LatLng vertA, LatLng vertB) {
    final double aY = vertA.latitude;
    final double bY = vertB.latitude;
    final double aX = vertA.longitude;
    final double bX = vertB.longitude;
    final double pY = point.latitude;
    final double pX = point.longitude;

    if ((aY > pY && bY > pY) || (aY < pY && bY < pY) || (aX < pX && bX < pX)) {
      return false;
    }
    final double m = (aY - bY) / (aX - bX);
    final double bee = (-aX) * m + aY;
    final double x = (pY - bee) / m;
    return x > pX;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location on the map'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final surveyProvider = context.read<SurveyProvider>();
    final authProvider = context.read<AuthProvider>();
    final fraudProvider = context.read<FraudDetectionProvider>();

    if (surveyProvider.selectedSurveyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a survey first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 🆕 NEW: Final fraud check before submit
    if (!_bypassFraudWarning) {
      final quickCheck = await fraudProvider.quickCheck(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
        _currentPosition?.accuracy,
      );

      if (quickCheck.isPotentiallyFraudulent) {
        _showFraudWarningDialog(quickCheck.reason, quickCheck.confidence);
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final String name = _nameController.text.trim();
      final String? phone = _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim();
      final String? address = _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim();
      final String? regionCode = _regionCodeController.text.trim().isEmpty
          ? null
          : _regionCodeController.text.trim();

      final respondentData = {
        'name': name,
        'phone': phone,
        'address': address,
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'location': {
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
        },
        'status': 'pending',
        'survey_id': surveyProvider.selectedSurveyId,
        'enumerator_id': authProvider.user?.id,
        // 🆕 NEW: Add fraud check info
        'fraud_bypassed': _bypassFraudWarning,
        'gps_accuracy': _currentPosition?.accuracy,
        'region_code': regionCode,
      };

      await ApiService.instance.createRespondent(respondentData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(_bypassFraudWarning
                    ? 'Respondent added (with warning bypass)'
                    : 'Respondent added successfully!'),
              ],
            ),
            backgroundColor: _bypassFraudWarning ? Colors.orange : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Respondent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Change Base Map',
            onPressed: _showBaseMapSelector,
          ),
        ],
      ),
      body: Column(
        children: [
          // Map Section
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Map
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: _selectedLocation ?? const LatLng(-6.2088, 106.8456),
                    zoom: 17,
                    maxZoom: 20,
                    minZoom: 5,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _getTileUrl(),
                      userAgentPackageName: 'com.fieldtracker.app',
                      maxZoom: 20,
                    ),
                    PolygonLayer(
                      polygons: _visualPolygons,
                    ),
                    MarkerLayer(
                      markers: [
                        if (_currentPosition != null)
                          Marker(
                            point: LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            ),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.3),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue, width: 2),
                              ),
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                          ),
                        if (_selectedLocation != null)
                          Marker(
                            point: _selectedLocation!,
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 50,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                if (_isLoadingLocation || _isValidatingLocation)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(_isValidatingLocation
                                  ? 'Validating location...'
                                  : 'Getting your location...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // 🆕 NEW: Fraud warning banner
                if (_bypassFraudWarning)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Peringatan lokasi diabaikan',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() => _bypassFraudWarning = false);
                              _validateCurrentLocation();
                            },
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Base map indicator
                if (!_bypassFraudWarning)
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

                if (_selectedLocation != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
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
                          const Icon(Icons.location_on, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Selected Location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Positioned(
                  top: _bypassFraudWarning ? 80 : 16,
                  right: 16,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'basemap_add',
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
                        heroTag: 'mylocation_add',
                        mini: true,
                        backgroundColor: Colors.white,
                        onPressed: () {
                          setState(() => _useCurrentLocation = true);
                          _getCurrentLocation();
                        },
                        child: const Icon(
                          Icons.my_location,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  top: _bypassFraudWarning ? 140 : 70,
                  left: 16,
                  right: 70,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap on the map to set respondent location',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Form Section
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: 20 + bottomPadding,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Respondent Name *',
                          prefixIcon: Icon(Icons.person),
                          hintText: 'Enter respondent name',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter respondent name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _regionCodeController,
                              readOnly: !_isRegionCodeEditable, // Logika ReadOnly
                              style: TextStyle(
                                // Hitam jika diedit, abu-abu jika otomatis
                                color: !_isRegionCodeEditable ? Colors.grey[700] : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Kode Wilayah (Auto)',
                                hintText: 'Pilih lokasi di peta...',
                                prefixIcon: const Icon(Icons.map_outlined),
                                filled: !_isRegionCodeEditable,
                                fillColor: Colors.grey[100],
                                border: const OutlineInputBorder(),
                                helperText: 'Otomatis terisi berdasarkan Pin Peta',
                              ),
                              // Validasi: Wajib ada isinya
                              validator: (value) =>
                              value?.isEmpty ?? true ? 'Lokasi belum terpilih di peta' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Tombol Gembok (Toggle Edit)
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: IconButton(
                              icon: Icon(
                                _isRegionCodeEditable ? Icons.lock_open : Icons.lock,
                                color: _isRegionCodeEditable ? Colors.red : Colors.green,
                              ),
                              tooltip: _isRegionCodeEditable ? 'Kunci Field' : 'Edit Manual',
                              onPressed: () {
                                setState(() {
                                  _isRegionCodeEditable = !_isRegionCodeEditable;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone),
                          hintText: 'Enter phone number (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          prefixIcon: Icon(Icons.home),
                          hintText: 'Enter address (optional)',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submitForm,
                        icon: _isSubmitting
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Icon(Icons.save),
                        label: Text(_isSubmitting ? 'Saving...' : 'Save Respondent'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: _bypassFraudWarning
                              ? Colors.orange
                              : const Color(0xFF4CAF50),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}