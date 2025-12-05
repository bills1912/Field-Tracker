import 'dart:async'; // Tambahkan ini untuk Future
import 'dart:ui' as ui; // 1. Tambahkan import ini untuk ui.Codec
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/offline_map_service.dart'; // Pastikan path ini benar sesuai struktur folder Anda

/// Custom tile provider yang mendukung offline caching
class OfflineTileProvider extends TileProvider {
  final String urlTemplate;
  final String providerName;
  final bool enableCaching;

  OfflineTileProvider({
    required this.urlTemplate,
    required this.providerName,
    this.enableCaching = true,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return OfflineTileImage(
      x: coordinates.x,
      y: coordinates.y,
      z: coordinates.z,
      urlTemplate: urlTemplate,
      providerName: providerName,
      enableCaching: enableCaching,
    );
  }
}

/// Custom image provider untuk offline tiles
class OfflineTileImage extends ImageProvider<OfflineTileImage> {
  final int x;
  final int y;
  final int z;
  final String urlTemplate;
  final String providerName;
  final bool enableCaching;

  OfflineTileImage({
    required this.x,
    required this.y,
    required this.z,
    required this.urlTemplate,
    required this.providerName,
    required this.enableCaching,
  });

  @override
  Future<OfflineTileImage> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }



  @override
  ImageStreamCompleter loadImage(
      OfflineTileImage key,
      ImageDecoderCallback decode,
      ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(decode),
      scale: 1.0,
      debugLabel: 'OfflineTileImage(${key.x},${key.y},${key.z})',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('URL', urlTemplate),
        DiagnosticsProperty<String>('Provider', providerName),
      ],
    );
  }

  // 2. Ubah tipe return menjadi Future<ui.Codec>
  Future<ui.Codec> _loadTile(ImageDecoderCallback decode) async {
    try {
      Uint8List? tileData;

      if (enableCaching) {
        // Try to get from cache or download
        tileData = await OfflineMapService.instance.getTile(
          x: x,
          y: y,
          z: z,
          provider: providerName,
          urlTemplate: urlTemplate,
        );
      }

      if (tileData != null && tileData.isNotEmpty) {
        // 3. Gunakan ui.ImmutableBuffer
        final buffer = await ui.ImmutableBuffer.fromUint8List(tileData);
        return decode(buffer);
      }

      // Return placeholder if no tile available
      return _getPlaceholderCodec(decode);
    } catch (e) {
      debugPrint('Error loading tile $z/$x/$y: $e');
      return _getPlaceholderCodec(decode);
    }
  }

  // 4. Ubah tipe return menjadi Future<ui.Codec>
  Future<ui.Codec> _getPlaceholderCodec(ImageDecoderCallback decode) async {
    // Create a simple gray placeholder tile
    final bytes = _createPlaceholderTile();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Uint8List _createPlaceholderTile() {
    // 1x1 transparent pixel PNG to prevent errors
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OfflineTileImage &&
        other.x == x &&
        other.y == y &&
        other.z == z &&
        other.providerName == providerName;
  }

  @override
  int get hashCode => Object.hash(x, y, z, providerName);

  @override
  String toString() => 'OfflineTileImage($providerName/$z/$x/$y)';
}

/// Helper class untuk membuat TileLayer dengan offline support
class OfflineMapHelper {
  /// Create an offline-capable TileLayer
  static TileLayer createOfflineTileLayer({
    required String urlTemplate,
    String providerName = 'osm',
    bool enableCaching = true,
    String userAgentPackageName = 'com.fieldtracker.app',
  }) {
    return TileLayer(
      urlTemplate: urlTemplate,
      tileProvider: OfflineTileProvider(
        urlTemplate: urlTemplate,
        providerName: providerName,
        enableCaching: enableCaching,
      ),
      userAgentPackageName: userAgentPackageName,
      maxNativeZoom: 19,
      maxZoom: 22,
      errorTileCallback: (tile, error, stackTrace) {
        debugPrint('Tile error at ${tile.coordinates}: $error');
      },
    );
  }

  /// URL templates for different map providers
  static const String osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String googleSatelliteUrl = 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
  static const String googleHybridUrl = 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
  static const String googleTerrainUrl = 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';

  /// Pre-download map tiles for offline use
  static Future<void> downloadAreaForOffline({
    required double centerLat,
    required double centerLon,
    required double radiusKm,
    int minZoom = 12,
    int maxZoom = 16,
    String urlTemplate = osmUrl,
    String providerName = 'osm',
    Function(int downloaded, int total)? onProgress,
  }) async {
    // Calculate bounding box
    final latDelta = radiusKm / 111.0; // 1 degree ≈ 111 km
    final lonDelta = radiusKm / (111.0 * 0.85); // Approximate for mid-latitudes

    await OfflineMapService.instance.downloadRegion(
      regionId: '${providerName}_${centerLat.toStringAsFixed(4)}_${centerLon.toStringAsFixed(4)}',
      regionName: 'Area around $centerLat, $centerLon',
      minLat: centerLat - latDelta,
      maxLat: centerLat + latDelta,
      minLon: centerLon - lonDelta,
      maxLon: centerLon + lonDelta,
      minZoom: minZoom,
      maxZoom: maxZoom,
      urlTemplate: urlTemplate,
      provider: providerName,
      onProgress: onProgress,
    );
  }

  /// Check if area is available offline
  static Future<bool> isAreaAvailableOffline(String regionId) async {
    return await OfflineMapService.instance.isRegionAvailableOffline(regionId);
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    return await OfflineMapService.instance.getCacheStats();
  }

  /// Clear map cache
  static Future<void> clearCache() async {
    await OfflineMapService.instance.clearAllCache();
  }
}

/// Widget untuk menampilkan status offline map
class OfflineMapStatusWidget extends StatelessWidget {
  final bool isOffline;
  final int cachedTiles;
  final VoidCallback? onDownloadPressed;

  const OfflineMapStatusWidget({
    super.key,
    required this.isOffline,
    this.cachedTiles = 0,
    this.onDownloadPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOffline
            ? Colors.orange.withOpacity(0.9)
            : Colors.green.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOffline ? Icons.cloud_off : Icons.cloud_done,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isOffline
                ? 'Offline Mode ($cachedTiles tiles cached)'
                : 'Online',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isOffline && onDownloadPressed != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDownloadPressed,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}