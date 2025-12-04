import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'; // Opsional: jika ingin mencatat region yang didownload
import 'package:path/path.dart' as p;

class OfflineMapService {
  static OfflineMapService? _instance;
  static OfflineMapService get instance => _instance ??= OfflineMapService._();

  OfflineMapService._();

  final Dio _dio = Dio();
  String? _tilesDirectory;

  // Inisialisasi direktori penyimpanan
  Future<String> get _basePath async {
    if (_tilesDirectory != null) return _tilesDirectory!;
    final dir = await getApplicationDocumentsDirectory();
    _tilesDirectory = p.join(dir.path, 'map_tiles');
    return _tilesDirectory!;
  }

  /// Mengambil Tile: Cek Disk -> Jika tidak ada & Online -> Download -> Simpan
  Future<Uint8List?> getTile({
    required int x,
    required int y,
    required int z,
    required String provider, // misal: 'osm' atau 'google'
    required String urlTemplate,
  }) async {
    try {
      final basePath = await _basePath;
      // Struktur folder: documents/map_tiles/osm/12/200/300.png
      final tilePath = p.join(basePath, provider, '$z', '$x', '$y.png');
      final file = File(tilePath);

      // 1. Cek Offline Cache
      if (await file.exists()) {
        return await file.readAsBytes();
      }

      // 2. Jika tidak ada di HP, coba download (On-the-fly caching)
      // Note: Logic ini berjalan saat user geser peta dalam keadaan Online
      final url = urlTemplate
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString())
          .replaceAll('{z}', z.toString());

      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );

        if (response.data != null) {
          // Simpan ke file untuk penggunaan offline nanti
          await file.parent.create(recursive: true);
          await file.writeAsBytes(response.data!);
          return Uint8List.fromList(response.data!);
        }
      } catch (e) {
        // Gagal download (mungkin offline total), biarkan return null
        // Provider akan menampilkan placeholder abu-abu
      }

      return null;
    } catch (e) {
      debugPrint('Error getting tile: $e');
      return null;
    }
  }

  /// Bulk Download (Fitur "Download Area Offline")
  Future<void> downloadRegion({
    required String regionId,
    required String regionName,
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int minZoom,
    required int maxZoom,
    required String urlTemplate,
    required String provider,
    Function(int current, int total)? onProgress,
  }) async {
    int totalTiles = 0;
    int downloadedTiles = 0;

    // 1. Hitung total tiles dulu
    for (int z = minZoom; z <= maxZoom; z++) {
      final p1 = _latLngToTile(minLat, minLon, z);
      final p2 = _latLngToTile(maxLat, maxLon, z);

      final xMin = min(p1.x, p2.x);
      final xMax = max(p1.x, p2.x);
      final yMin = min(p1.y, p2.y);
      final yMax = max(p1.y, p2.y);

      totalTiles += (xMax - xMin + 1) * (yMax - yMin + 1);
    }

    debugPrint('⬇️ Starting download for $regionName: $totalTiles tiles');

    // 2. Mulai Download Loop
    for (int z = minZoom; z <= maxZoom; z++) {
      final p1 = _latLngToTile(minLat, minLon, z);
      final p2 = _latLngToTile(maxLat, maxLon, z);

      final xMin = min(p1.x, p2.x);
      final xMax = max(p1.x, p2.x);
      final yMin = min(p1.y, p2.y);
      final yMax = max(p1.y, p2.y);

      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          // Panggil getTile agar mendownload & menyimpan
          await getTile(
              x: x,
              y: y,
              z: z,
              provider: provider,
              urlTemplate: urlTemplate
          );

          downloadedTiles++;
          onProgress?.call(downloadedTiles, totalTiles);

          // Beri jeda sedikit agar UI tidak freeze & tidak dianggap spam oleh server peta
          if (downloadedTiles % 10 == 0) await Future.delayed(const Duration(milliseconds: 10));
        }
      }
    }
    debugPrint('✅ Download completed for $regionName');
  }

  // --- Helper Methods ---

  Point<int> _latLngToTile(double lat, double lon, int zoom) {
    final n = pow(2, zoom);
    final x = ((lon + 180) / 360 * n).floor();
    final latRad = lat * pi / 180;
    final y = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n).floor();
    return Point(x, y);
  }

  Future<bool> isRegionAvailableOffline(String regionId) async {
    // Implementasi sederhana: Cek apakah folder provider ada isinya
    // Untuk produksi: Sebaiknya gunakan SQLite untuk mencatat region yang sudah selesai didownload
    final path = await _basePath;
    return Directory(path).existsSync();
  }

  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final dir = Directory(await _basePath);
      if (!dir.existsSync()) return {'count': 0, 'size_mb': 0.0};

      int count = 0;
      int sizeBytes = 0;

      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.png')) {
          count++;
          sizeBytes += await entity.length();
        }
      }

      return {
        'count': count,
        'size_mb': double.parse((sizeBytes / (1024 * 1024)).toStringAsFixed(2)),
      };
    } catch (e) {
      return {'count': 0, 'size_mb': 0.0};
    }
  }

  Future<void> clearAllCache() async {
    final dir = Directory(await _basePath);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}