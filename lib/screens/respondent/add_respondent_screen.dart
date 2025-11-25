// lib/screens/respondent/add_respondent_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../models/respondent.dart';
import '../../providers/auth_provider.dart';
import '../../providers/survey_provider.dart';
import '../../services/api_service.dart';

enum BaseMapType {
  openStreetMap,
  googleSatellite,
  googleHybrid,
}

class AddRespondentScreen extends StatefulWidget {
  const AddRespondentScreen({super.key});

  @override
  State<AddRespondentScreen> createState() => _AddRespondentScreenState();
}

class _AddRespondentScreenState extends State<AddRespondentScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      // Check permission
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

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        if (_useCurrentLocation) {
          _selectedLocation = LatLng(position.latitude, position.longitude);
        }
      });

      // Move map to current location
      if (_selectedLocation != null) {
        _mapController.move(_selectedLocation!, 17);
      }
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
    });
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

    if (surveyProvider.selectedSurveyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a survey first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final respondentData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'status': 'pending',
        'survey_id': surveyProvider.selectedSurveyId,
        'enumerator_id': authProvider.user?.id,
      };

      await ApiService.instance.createRespondent(respondentData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Respondent added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding respondent: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    // Markers
                    MarkerLayer(
                      markers: [
                        // Current location marker (blue)
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
                        // Selected location marker (red pin)
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

                // Loading indicator
                if (_isLoadingLocation)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Getting your location...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Base Map Indicator
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

                // Location info
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

                // FAB for current location
                Positioned(
                  top: 16,
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

                // Instruction overlay
                Positioned(
                  top: 70,
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
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Name Field
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

                      // Phone Field
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

                      // Address Field
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
                          backgroundColor: const Color(0xFF4CAF50),
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