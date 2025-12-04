// lib/screens/map/survey_map_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:field_tracker/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
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
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../providers/offline_tile_provider.dart'; // Sesuaikan path tempat Anda menyimpan file yang diupload tadi
import '../../services/offline_map_service.dart';
import '../../services/storage_service.dart';

enum BaseMapType {
  openStreetMap,
  googleSatellite,
  googleHybrid,
}

/// Survey-specific Map Screen with respondent filtering and GeoJSON support
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
  bool _isFabOpen = false;
  final Map<String, String> _regionPcodes = {};
  // String? _selectedRegionPcode;
  List<Respondent> _masterRespondentsList = []; // Menyimpan semua data dari API
  String? _cachedGeoJsonString; // Menyimpan text file GeoJSON
  List<String> _myAllocatedRegions = [];

  // Navigation state
  bool _isNavigating = false;
  Respondent? _navigationTarget;
  StreamSubscription<Position>? _positionSubscription;
  double? _distanceToTarget;
  double? _bearingToTarget;

  // GeoJSON state
  GeoJsonParser? _geoJsonParser;
  bool _isLoadingGeoJson = false;
  bool _showGeoJson = true;
  List<String> _availableRegions = [];
  String? _selectedRegion;
  bool _isRegionSelectorOpen = false;

  // Tile URLs
  static const String _googleSatelliteUrl =
      'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  static const String _googleHybridUrl =
      'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
  static const String _openStreetMapUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double _mainFabSize = 56.0;


  @override
  void initState() {
    super.initState();
    _currentFilter = widget.statusFilter;
    _loadMapData();
    _getCurrentLocation();
    _loadGeoJson();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// Load GeoJSON data for the survey
  Future<void> _loadGeoJson() async {
    if (widget.survey.geojsonPath == null) {
      debugPrint('ℹ️ No GeoJSON path for this survey');
      return;
    }

    setState(() => _isLoadingGeoJson = true);

    try {
      debugPrint('📍 Loading GeoJSON from: ${widget.survey.geojsonPath}');

      String geoJsonString;

      // CEK: Apakah path adalah URL Online?
      if (widget.survey.geojsonPath!.startsWith('http')) {
        // --- LOGIC BARU: Fetch dari API ---

        // Ambil token dari AuthProvider untuk otentikasi
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final token = authProvider.token; // Pastikan AuthProvider punya getter 'token'

        final response = await http.get(
          Uri.parse(widget.survey.geojsonPath!),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          geoJsonString = response.body;
          // Cache string agar tidak request ulang jika rebuild
          _cachedGeoJsonString = geoJsonString;
        } else {
          throw Exception('Failed to download map: ${response.statusCode}');
        }
      } else {
        // --- LOGIC LAMA: Load dari Asset Lokal (Mock) ---
        _cachedGeoJsonString ??= await rootBundle.loadString(widget.survey.geojsonPath!);
        geoJsonString = _cachedGeoJsonString!;
      }

      // Parse GeoJSON
      _geoJsonParser = GeoJsonParser(
        defaultPolygonFillColor: Colors.blue.withOpacity(0.1),
        defaultPolygonBorderColor: Colors.blue,
        defaultPolygonBorderStroke: 2.0,
      );

      _geoJsonParser!.parseGeoJsonAsString(geoJsonString);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;

      // Cek apakah ada data alokasi di survey ini
      if (widget.survey.allocations.isNotEmpty && user != null) {

        // Jika Admin, tampilkan semua. Jika bukan, filter.
        if (user.role != 'admin') { // Sesuaikan string role admin Anda

          // Ambil daftar nama region yang ditugaskan ke user ini
          _myAllocatedRegions = widget.survey.allocations
              .where((a) => a.enumeratorId == user.id || a.supervisorId == user.id)
              .map((a) => a.region)
              .toList();

          debugPrint('🎯 User Allocated Regions: $_myAllocatedRegions');

          // Jika user punya alokasi, HAPUS polygon yang tidak sesuai
          if (_myAllocatedRegions.isNotEmpty) {
            // Filter polygons di _geoJsonParser
            // Note: flutter_map_geojson mungkin tidak menyimpan nama di objek Polygon-nya secara langsung
            // Jadi kita harus filter ulang stringnya ATAU filter polygons-nya jika kita bisa map index-nya.
            // Cara paling aman & bersih: Filter String GeoJSON-nya SEBELUM diparsing ke Parser Visual.

            final filteredString = _filterGeoJsonStringByList(
                geoJsonString,
                widget.survey.geojsonFilterField ?? 'ADM3_EN',
                _myAllocatedRegions
            );

            // Reset parser dengan string yang sudah disaring
            _geoJsonParser = GeoJsonParser(
              defaultPolygonFillColor: Colors.blue.withOpacity(0.1),
              defaultPolygonBorderColor: Colors.blue,
              defaultPolygonBorderStroke: 2.0,
            );
            _geoJsonParser!.parseGeoJsonAsString(filteredString);

            // Update cache string agar _filterGeoJsonByRegion (dropdown select) pakai data yang sudah disaring
            _cachedGeoJsonString = filteredString;
            geoJsonString = filteredString; // Update variabel lokal untuk ekstraksi di bawah
          }
        }
      }

      // Extract available regions from GeoJSON
      if (widget.survey.geojsonFilterField != null) {
        _extractRegionsFromGeoJson(geoJsonString);
      }

      debugPrint('✅ GeoJSON loaded successfully');
      debugPrint('   Polygons: ${_geoJsonParser!.polygons.length}');
      debugPrint('   Available regions: ${_availableRegions.length}');

      setState(() => _isLoadingGeoJson = false);
    } catch (e) {
      debugPrint('❌ Error loading GeoJSON: $e');
      setState(() => _isLoadingGeoJson = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading map boundary: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // --- MULAI COPY DARI SINI ---

  /// Fungsi ini adalah "Jembatan" antara UI dengan Logic Download
  Future<void> _downloadCurrentArea() async {
    // 1. Cek apakah peta sudah siap
    if (_mapController.center.latitude == 0 && _mapController.center.longitude == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tunggu peta dimuat sepenuhnya')),
      );
      return;
    }

    // 2. Tampilkan Dialog Progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String status = "Menyiapkan download...";
          double progress = 0.0;

          // 3. PANGGIL MESINNYA DI SINI (OfflineMapHelper.downloadAreaForOffline)
          OfflineMapHelper.downloadAreaForOffline(
            centerLat: _mapController.center.latitude,
            centerLon: _mapController.center.longitude,
            radiusKm: 2.0, // Radius 2 KM dari tengah layar
            minZoom: 12,   // Zoom level kecamatan
            maxZoom: 18,   // Zoom level detail jalan
            urlTemplate: _getTileUrl(),
            providerName: _currentBaseMap.name,
            onProgress: (downloaded, total) {
              // Update tampilan loading
              setDialogState(() {
                if (total > 0) progress = downloaded / total;
                status = "Mendownload tile $downloaded / $total";
              });
            },
          ).then((_) {
            // Jika Selesai: Tutup dialog & Beri info sukses
            Navigator.of(ctx, rootNavigator: true).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Area berhasil disimpan offline!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }).catchError((error) {
            // Jika Error: Tutup dialog & Beri info error
            Navigator.of(ctx, rootNavigator: true).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Gagal: $error'), backgroundColor: Colors.red),
              );
            }
          });

          // Tampilan Dialog
          return AlertDialog(
            title: const Text('Download Peta Offline'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                const Text(
                    'Mohon tunggu, butuh koneksi internet.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  // --- SELESAI COPY ---

  String _filterGeoJsonStringByList(String geoJsonString, String fieldName, List<String> allowedRegions) {
    try {
      final data = jsonDecode(geoJsonString);
      if (data['features'] == null) return geoJsonString;

      final List features = data['features'];
      final List filteredFeatures = features.where((feature) {
        final props = feature['properties'];
        if (props == null) return false;

        final regionName = props[fieldName];
        // Keep if regionName exists in allowed list
        return allowedRegions.contains(regionName);
      }).toList();

      data['features'] = filteredFeatures;
      return jsonEncode(data);
    } catch (e) {
      debugPrint('⚠️ Error filtering GeoJSON by list: $e');
      return geoJsonString;
    }
  }

  /// Extract region names from GeoJSON features
  void _extractRegionsFromGeoJson(String geoJsonString) {
    try {
      _availableRegions.clear();
      _regionPcodes.clear();

      final data = jsonDecode(geoJsonString);
      if (data['features'] != null) {
        final features = data['features'] as List;
        final Set<String> regions = {};

        // Field nama (default ADM3_EN) dan field code (default ADM3_PCODE)
        final nameField = widget.survey.geojsonFilterField ?? 'ADM3_EN';
        final codeField = widget.survey.geojsonUniqueCodeField ?? 'ADM3_PCODE';

        for (var feature in features) {
          final props = feature['properties'];
          if (props != null) {
            final name = props[nameField];
            final code = props[codeField];

            if (name != null && name.toString().isNotEmpty) {
              regions.add(name);
              // Simpan mapping Nama -> PCODE
              if (code != null) {
                _regionPcodes[name] = code.toString();
              }
            }
          }
        }
        _availableRegions = regions.toList()..sort();
        debugPrint('📊 Extracted ${_availableRegions.length} regions with codes');
      }
    } catch (e) {
      debugPrint('⚠️ Error extracting regions: $e');
    }
  }

  /// Filter GeoJSON to show only selected region
  Future<void> _filterGeoJsonByRegion(String? regionName) async {
    setState(() => _isLoadingGeoJson = true);

    try {

      if (_cachedGeoJsonString == null) {
        // Jika belum ada (misal karena refresh), download ulang
        await _loadGeoJson();

        // Jika masih gagal download, hentikan proses
        if (_cachedGeoJsonString == null) {
          setState(() => _isLoadingGeoJson = false);
          return;
        }
      }

      final String geoJsonString = _cachedGeoJsonString!;

      // 1. Ambil Target Code dari Map yang sudah diekstrak sebelumnya
      String? targetCode;
      if (regionName != null) {
        targetCode = _regionPcodes[regionName]; // Mengambil kode (misal: "3507010")
        _selectedRegion = regionName;
      } else {
        _selectedRegion = null;
      }

      // 2. Ambil data mentah (Semua Responden)
      final allData = await ApiService.instance.getRespondents(
        surveyId: widget.survey.id,
      );

      _geoJsonParser = GeoJsonParser(
        defaultPolygonFillColor: Colors.blue.withOpacity(0.2),
        defaultPolygonBorderColor: Colors.blue,
        defaultPolygonBorderStroke: 2.5,
      );

      if (regionName != null && targetCode != null) {
        // A. Filter Visual (Polygon Peta)
        final filteredGeoJson = _filterGeoJsonString(
          geoJsonString,
          widget.survey.geojsonFilterField ?? 'ADM3_EN',
          regionName,
        );
        _geoJsonParser!.parseGeoJsonAsString(filteredGeoJson);
        _zoomToRegion(regionName);

        // B. Filter Data Responden (LOGIKA UTAMA)
        // Cocokkan 'regionCode' di model dengan 'targetCode' dari GeoJSON
        _allRespondents = allData.where((r) {
          // Debugging (Opsional: Cek di console jika data tidak muncul)
          // debugPrint('Cek: ${r.name} | RegionCode: ${r.regionCode} vs Target: $targetCode');

          if (r.region_code == null) return false;
          return r.region_code == targetCode; // Pencocokan terjadi di sini
        }).toList();

      } else {
        // Tampilkan Semua (Jika tidak pilih region)
        _geoJsonParser!.parseGeoJsonAsString(geoJsonString);
        _allRespondents = allData;
        _centerMapOnContent();
      }

      // 3. Terapkan Filter Status (Pending/Completed) ke hasil filter wilayah
      _applyFilter();

      setState(() => _isLoadingGeoJson = false);

      if (regionName != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Region: $regionName (Found ${_allRespondents.length} respondents)'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error filtering GeoJSON: $e');
      setState(() => _isLoadingGeoJson = false);
    }
  }

  /// Filter GeoJSON string to include only specified region
  String _filterGeoJsonString(String geoJsonString, String fieldName, String regionName) {
    try {
      // Simple string-based filtering for the GeoJSON
      // This creates a new FeatureCollection with only matching features

      final RegExp featurePattern = RegExp(
        r'\{[^{}]*"type"\s*:\s*"Feature"[^{}]*"properties"\s*:\s*\{[^}]*"' +
            fieldName +
            r'"\s*:\s*"' +
            RegExp.escape(regionName) +
            r'"[^}]*\}[^{}]*"geometry"[^{}]*\{[^{}]*\}[^{}]*\}',
        multiLine: true,
        dotAll: true,
      );

      final matches = featurePattern.allMatches(geoJsonString);

      if (matches.isEmpty) {
        return geoJsonString; // Return original if no match
      }

      final features = matches.map((m) => m.group(0)).join(',');

      return '''
{
  "type": "FeatureCollection",
  "features": [$features]
}
''';
    } catch (e) {
      debugPrint('⚠️ Error in filter: $e');
      return geoJsonString;
    }
  }

  /// Zoom map to selected region
  void _zoomToRegion(String regionName) {
    if (_geoJsonParser == null || _geoJsonParser!.polygons.isEmpty) return;

    try {
      // Calculate bounds of all polygons in the selected region
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLon = double.infinity;
      double maxLon = double.negativeInfinity;

      for (var polygon in _geoJsonParser!.polygons) {
        for (var point in polygon.points) {
          minLat = min(minLat, point.latitude);
          maxLat = max(maxLat, point.latitude);
          minLon = min(minLon, point.longitude);
          maxLon = max(maxLon, point.longitude);
        }
      }

      if (minLat.isFinite && maxLat.isFinite && minLon.isFinite && maxLon.isFinite) {
        final bounds = LatLngBounds(
          LatLng(minLat, minLon),
          LatLng(maxLat, maxLon),
        );

        _mapController.fitBounds(
          bounds,
          options: const FitBoundsOptions(
            padding: EdgeInsets.all(50),
            maxZoom: 14,
          ),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error zooming to region: $e');
    }
  }

  /// Show region selector dialog
  void _showRegionSelector() {
    if (_availableRegions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No regions available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.layers, color: Color(0xFF2196F3)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Select Region',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_selectedRegion != null)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _filterGeoJsonByRegion(null);
                          },
                          child: const Text('Show All'),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Region list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _availableRegions.length,
                itemBuilder: (context, index) {
                  final regionName = _availableRegions[index];
                  final isSelected = _selectedRegion == regionName;

                  return Card(
                    elevation: isSelected ? 4 : 1,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isSelected
                          ? const BorderSide(color: Color(0xFF2196F3), width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2196F3)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: isSelected ? Colors.white : Colors.grey[600],
                        ),
                      ),
                      title: Text(
                        regionName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF2196F3) : null,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF2196F3))
                          : const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(context);
                        _filterGeoJsonByRegion(regionName);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMapData() async {
    setState(() => _isLoading = true);

    try {
      // Load respondents for this specific survey
      final respondents = await ApiService.instance.getRespondents(
        surveyId: widget.survey.id,
      );
      final allPending = await StorageService.instance.getPendingRespondents();
      final thisSurveyPending = allPending.where((r) => r.surveyId == widget.survey.id).toList();

      // 3. Gabungkan Data (Hindari duplikat jika ID pending bertabrakan)
      final Map<String, Respondent> uniqueMap = {};

      // Masukkan server dulu
      for (var r in respondents) uniqueMap[r.id] = r;

      // Timpa/Tambah dengan pending (Pending lebih prioritas untuk ditampilkan status terbarunya)
      for (var r in thisSurveyPending) uniqueMap[r.id] = r;

      setState(() {
        _masterRespondentsList = respondents;
        _allRespondents = respondents;
        _applyFilter();
      });

      if (thisSurveyPending.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Menampilkan ${thisSurveyPending.length} data yang belum disinkronisasi'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
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
    setState(() {
      if (_allRespondents.isEmpty) {
        _filteredRespondents = [];
      } else if (_currentFilter == null) {
        // Jika Status Filter = Semua
        _filteredRespondents = List.from(_allRespondents);
      } else {
        // Jika Status Filter = Pending/In Progress/Completed
        _filteredRespondents = _allRespondents
            .where((r) => r.status == _currentFilter)
            .toList();
      }
    });

    debugPrint('🔍 Filter Update: Total ${_allRespondents.length} -> Show ${_filteredRespondents.length}');
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

  // ==================== VIEW MODE TOGGLE BUTTON ====================

  Widget _buildViewModeButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected
                ? const Color(0xFF2196F3)
                : Colors.white.withOpacity(0.8),
          ),
        ),
      ),
    );
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

  Widget _buildMiniFab({
    required String heroTag,
    required VoidCallback onPressed,
    required IconData icon,
    Color? backgroundColor,
    Color? iconColor,
    Widget? badge,
  }) {
    return SizedBox(
      width: _mainFabSize,              // samakan lebar dengan FAB utama
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton(
              heroTag: heroTag,
              mini: true,
              backgroundColor: backgroundColor ?? Colors.white,
              onPressed: onPressed,
              child: Icon(
                icon,
                color: iconColor ?? const Color(0xFF2196F3),
              ),
            ),
            if (badge != null)
              Positioned(
                right: -4,
                top: -4,
                child: badge,
              ),
          ],
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
          // View Mode Toggle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewModeButton(
                  icon: Icons.map,
                  isSelected: _viewMode == 'map',
                  onTap: () => setState(() => _viewMode = 'map'),
                  tooltip: 'Map View',
                ),
                _buildViewModeButton(
                  icon: Icons.list,
                  isSelected: _viewMode == 'list',
                  onTap: () => setState(() => _viewMode = 'list'),
                  tooltip: 'List View',
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // More Options Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More Options',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            offset: const Offset(0, 45),
            onSelected: (value) async {
              switch (value) {
                case 'filter':
                  _showFilterSheet();
                  break;
                case 'basemap':
                  _showBaseMapSelector();
                  break;
                case 'refresh':
                  if (networkProvider.isConnected) _loadMapData();
                  break;
                case 'add':
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddRespondentScreen(
                        geojsonPath: widget.survey.geojsonPath,
                        allowedRegions: _myAllocatedRegions.isNotEmpty ? _myAllocatedRegions : null,
                      ),
                    ),
                  );
                  if (result == true) {
                    _loadMapData();
                  }
                  break;
                case 'download_offline':
                  _downloadCurrentArea();
                  break;
                case 'legend':
                  _showLegend();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'filter',
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list,
                      color: _currentFilter != null
                          ? _getMarkerColor(_currentFilter!)
                          : const Color(0xFF2196F3),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Filter Responden'),
                          Text(
                            _getFilterLabel(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'basemap',
                child: Row(
                  children: [
                    Icon(
                      _getBaseMapIcon(_currentBaseMap),
                      color: const Color(0xFF2196F3),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Base Map'),
                          Text(
                            _getBaseMapName(_currentBaseMap),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'refresh',
                enabled: networkProvider.isConnected,
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh,
                      color: networkProvider.isConnected
                          ? const Color(0xFF2196F3)
                          : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Refresh Data',
                      style: TextStyle(
                        color: networkProvider.isConnected
                            ? null
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'legend',
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF2196F3),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text('Legend'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'download_offline',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline, color: Colors.orange),
                    SizedBox(width: 12),
                    Text('Download Area (Offline)'),
                  ],
                ),
              ),
              if (user?.role == UserRole.enumerator) ...[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'add',
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle,
                        color: Color(0xFF4CAF50),
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Tambah Responden',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
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
          // Loading indicator for GeoJSON
          if (_isLoadingGeoJson)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
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
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF2196F3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Loading boundary...',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _viewMode == 'map' && !_isNavigating
          ? Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isFabOpen) ...[
            // GeoJSON Region Selector - Only show if GeoJSON is available
            if (widget.survey.geojsonPath != null && _availableRegions.isNotEmpty)
              _buildMiniFab(
                heroTag: 'region_selector',
                backgroundColor: _selectedRegion != null
                    ? const Color(0xFF2196F3)
                    : Colors.white,
                onPressed: _showRegionSelector,
                icon: Icons.location_pin,
                iconColor: _selectedRegion != null
                    ? Colors.white
                    : const Color(0xFF2196F3),
                badge: _selectedRegion != null
                    ? Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: Colors.white,
                  ),
                )
                    : null,
              ),
            if (widget.survey.geojsonPath != null && _availableRegions.isNotEmpty)
              const SizedBox(height: 8),
            // GeoJSON Toggle - Only show if GeoJSON is available
            if (widget.survey.geojsonPath != null)
              _buildMiniFab(
                heroTag: 'geojson_toggle',
                backgroundColor: _showGeoJson
                    ? const Color(0xFF4CAF50)
                    : Colors.white,
                onPressed: () {
                  setState(() => _showGeoJson = !_showGeoJson);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _showGeoJson
                            ? 'Boundary shown'
                            : 'Boundary hidden',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: Icons.border_outer,
                iconColor: _showGeoJson
                    ? Colors.white
                    : const Color(0xFF2196F3),
              ),
            if (widget.survey.geojsonPath != null)
              const SizedBox(height: 8),
            _buildMiniFab(
              heroTag: 'filter',
              backgroundColor: _currentFilter != null
                  ? _getMarkerColor(_currentFilter!)
                  : Colors.white,
              onPressed: _showFilterSheet,
              icon: Icons.filter_list,
              iconColor: _currentFilter != null
                  ? Colors.white
                  : const Color(0xFF2196F3),
            ),
            const SizedBox(height: 8),
            _buildMiniFab(
              heroTag: 'basemap',
              backgroundColor: Colors.white,
              onPressed: _showBaseMapSelector,
              icon: _getBaseMapIcon(_currentBaseMap),
              iconColor: const Color(0xFF2196F3),
            ),
            const SizedBox(height: 8),
            _buildMiniFab(
              heroTag: 'location',
              backgroundColor: Colors.white,
              onPressed: _getCurrentLocation,
              icon: Icons.my_location,
              iconColor: Color(0xFF2196F3),
            ),
            const SizedBox(height: 8),
            _buildMiniFab(
              heroTag: 'fit',
              backgroundColor: Colors.white,
              onPressed: _centerMapOnContent,
              icon: Icons.fit_screen,
              iconColor: Color(0xFF2196F3),
            ),
            const SizedBox(height: 8),
            _buildMiniFab(
              heroTag: 'legend',
              backgroundColor: Colors.white,
              onPressed: _showLegend,
              icon: Icons.info_outline,
              iconColor: Color(0xFF2196F3),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'mainFab',
            onPressed: () {
              setState(() {
                _isFabOpen = !_isFabOpen;
              });
            },
            child: Icon(
                _isFabOpen ? Icons.close : Icons.menu
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
            OfflineMapHelper.createOfflineTileLayer(
              urlTemplate: _getTileUrl(),
              providerName: _currentBaseMap.name, // 'openStreetMap' dll
              userAgentPackageName: 'com.fieldtracker.app',
            ),
            // GeoJSON Polygon Layer
            if (_showGeoJson && _geoJsonParser != null && !_isLoadingGeoJson)
              PolygonLayer(
                polygons: _geoJsonParser!.polygons,
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
        if (!_isNavigating && !_isLoadingGeoJson)
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_filteredRespondents.length} Responden (${_getFilterLabel()})',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_selectedRegion != null)
                          Text(
                            'Region: $_selectedRegion',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
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
            if (widget.survey.geojsonPath != null)
              _buildLegendItem(
                Colors.blue.withOpacity(0.3),
                'Survey Boundary',
                Icons.border_outer,
              ),
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