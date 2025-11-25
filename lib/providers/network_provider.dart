import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

class NetworkProvider with ChangeNotifier {
  bool _isConnected = true;
  int _pendingSync = 0;
  Timer? _syncTimer;

  bool get isConnected => _isConnected;
  int get pendingSync => _pendingSync;

  NetworkProvider() {
    _initConnectivity();
    _startAutoSync();
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    
    // Check initial connectivity
    final result = await connectivity.checkConnectivity();
    _isConnected = result != ConnectivityResult.none;
    notifyListeners();

    // Listen to connectivity changes
    connectivity.onConnectivityChanged.listen((result) async {
      final wasConnected = _isConnected;
      _isConnected = result != ConnectivityResult.none;
      
      // Auto-sync when coming online
      if (_isConnected && !wasConnected) {
        await syncNow();
      }
      
      notifyListeners();
    });

    // Update pending count
    await _updatePendingCount();
  }

  void _startAutoSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (_isConnected) {
        await syncNow();
      }
    });
  }

  Future<void> syncNow() async {
    if (!_isConnected) return;
    
    await SyncService.instance.syncAll();
    await _updatePendingCount();
    notifyListeners();
  }

  Future<void> _updatePendingCount() async {
    _pendingSync = await StorageService.instance.getPendingCount();
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}