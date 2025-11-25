// lib/screens/map/map_screen.dart
import 'package:field_tracker/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../models/respondent.dart';
import '../../models/location_tracking.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMapData();
    _getCurrentLocation();
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
      final position = await Geolocator.getCurrentPosition();
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final networkProvider = context.watch<NetworkProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Locations'),
        actions: [
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
              onPressed: () {
                // Navigate to add respondent
                Navigator.pushNamed(context, '/add-respondent');
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _viewMode == 'map'
              ? _buildMapView()
              : _buildListView(),
      floatingActionButton: _viewMode == 'map'
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fieldtracker.app',
            ),
            MarkerLayer(
              markers: [
                // User's current location
                if (_myPosition != null)
                  Marker(
                    point: LatLng(_myPosition!.latitude, _myPosition!.longitude),
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                  ),
                
                // Respondents
                ..._respondents.map((respondent) {
                  return Marker(
                    point: LatLng(respondent.latitude, respondent.longitude),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _showRespondentDetails(respondent),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getMarkerColor(respondent.status),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.location_on, color: Colors.white, size: 20),
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
                      ),
                      child: const Icon(Icons.person_pin, color: Colors.white, size: 20),
                    ),
                  );
                }),
              ],
            ),
          ],
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
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getMarkerColor(respondent.status),
              child: const Icon(Icons.location_on, color: Colors.white),
            ),
            title: Text(respondent.name),
            subtitle: Text(
              'Status: ${respondent.status.name.replaceAll('_', ' ')}\n'
              '${respondent.latitude.toStringAsFixed(6)}, ${respondent.longitude.toStringAsFixed(6)}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.directions),
              onPressed: () => _navigateToRespondent(respondent),
            ),
            onTap: () => _showRespondentDetails(respondent),
          ),
        );
      },
    );
  }

  void _showRespondentDetails(Respondent respondent) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              respondent.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.phone, 'Phone', respondent.phone ?? 'N/A'),
            _buildInfoRow(Icons.home, 'Address', respondent.address ?? 'N/A'),
            _buildInfoRow(
              Icons.location_on,
              'Location',
              '${respondent.latitude.toStringAsFixed(6)}, ${respondent.longitude.toStringAsFixed(6)}',
            ),
            _buildInfoRow(
              Icons.info,
              'Status',
              respondent.status.name.replaceAll('_', ' ').toUpperCase(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.directions),
                    label: const Text('Navigate'),
                    onPressed: () {
                      Navigator.pop(context);
                      _navigateToRespondent(respondent);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Update'),
                    onPressed: () {
                      Navigator.pop(context);
                      _updateRespondentStatus(respondent);
                    },
                  ),
                ),
              ],
            ),
          ],
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

  void _navigateToRespondent(Respondent respondent) {
    // Open Google Maps or similar navigation app
    // Implementation depends on url_launcher package
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Navigation feature - Install url_launcher package')),
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
                      const SnackBar(content: Text('Status updated successfully')),
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
}