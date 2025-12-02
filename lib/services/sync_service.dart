import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Sync Service untuk mengelola sinkronisasi data offline
class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();

  SyncService._();

  bool _isSyncing = false;
  Timer? _autoSyncTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// Initialize auto-sync when connectivity changes
  void init() {
    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          (ConnectivityResult result) async {
        if (result != ConnectivityResult.none) {
          debugPrint('🌐 Network connected, starting auto-sync...');
          await syncAll();
        }
      },
    );

    // Start periodic sync every 2 minutes
    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 2),
          (timer) async {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity != ConnectivityResult.none) {
          await syncAll();
        }
      },
    );

    debugPrint('✅ SyncService initialized');
  }

  /// Stop auto-sync
  void dispose() {
    _autoSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
  }

  /// Sync all pending data
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      debugPrint('⚠️ Sync already in progress');
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    _isSyncing = true;

    int syncedLocations = 0;
    int syncedRespondents = 0;
    int syncedMessages = 0;
    List<String> errors = [];

    try {
      debugPrint('🔄 Starting sync...');

      // Sync locations
      try {
        syncedLocations = await _syncLocations();
      } catch (e) {
        errors.add('Locations: $e');
        debugPrint('❌ Location sync error: $e');
      }

      // Sync respondents
      try {
        syncedRespondents = await _syncRespondents();
      } catch (e) {
        errors.add('Respondents: $e');
        debugPrint('❌ Respondent sync error: $e');
      }

      // Sync messages
      try {
        syncedMessages = await _syncMessages();
      } catch (e) {
        errors.add('Messages: $e');
        debugPrint('❌ Message sync error: $e');
      }

      final totalSynced = syncedLocations + syncedRespondents + syncedMessages;

      debugPrint('✅ Sync completed: $totalSynced items synced');
      debugPrint('   - Locations: $syncedLocations');
      debugPrint('   - Respondents: $syncedRespondents');
      debugPrint('   - Messages: $syncedMessages');

      return SyncResult(
        success: errors.isEmpty,
        message: errors.isEmpty
            ? 'Synced $totalSynced items'
            : 'Synced with errors: ${errors.join(", ")}',
        syncedLocations: syncedLocations,
        syncedRespondents: syncedRespondents,
        syncedMessages: syncedMessages,
        errors: errors,
      );
    } catch (e) {
      debugPrint('❌ Sync error: $e');
      return SyncResult(
        success: false,
        message: 'Sync failed: $e',
        errors: [e.toString()],
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync pending locations
  Future<int> _syncLocations() async {
    final pendingLocations = await StorageService.instance.getPendingLocations();

    if (pendingLocations.isEmpty) {
      debugPrint('📍 No pending locations to sync');
      return 0;
    }

    debugPrint('📍 Syncing ${pendingLocations.length} pending locations...');

    try {
      // Try batch sync first (more efficient)
      await ApiService.instance.createLocationsBatch(pendingLocations);
      await StorageService.instance.clearPendingLocations();
      debugPrint('✅ All locations synced via batch');
      return pendingLocations.length;
    } catch (batchError) {
      debugPrint('⚠️ Batch sync failed, trying individual sync: $batchError');

      // Fallback to individual sync
      int synced = 0;
      for (var location in pendingLocations) {
        try {
          await ApiService.instance.createLocation(location);
          synced++;
        } catch (e) {
          debugPrint('⚠️ Failed to sync location: $e');
        }
      }

      // Clear synced locations
      if (synced == pendingLocations.length) {
        await StorageService.instance.clearPendingLocations();
      }

      return synced;
    }
  }

  /// Sync pending respondents
  Future<int> _syncRespondents() async {
    final pendingRespondents = await StorageService.instance.getPendingRespondents();

    if (pendingRespondents.isEmpty) {
      debugPrint('👤 No pending respondents to sync');
      return 0;
    }

    debugPrint('👤 Syncing ${pendingRespondents.length} pending respondents...');

    int synced = 0;
    for (var respondent in pendingRespondents) {
      try {
        await ApiService.instance.createRespondent(respondent.toJson());
        await StorageService.instance.deletePendingRespondent(respondent.id);
        synced++;
        debugPrint('✅ Respondent ${respondent.name} synced');
      } catch (e) {
        debugPrint('⚠️ Failed to sync respondent ${respondent.name}: $e');
      }
    }

    return synced;
  }

  /// Sync pending messages
  Future<int> _syncMessages() async {
    final pendingMessages = await StorageService.instance.getPendingMessages();

    if (pendingMessages.isEmpty) {
      debugPrint('💬 No pending messages to sync');
      return 0;
    }

    debugPrint('💬 Syncing ${pendingMessages.length} pending messages...');

    int synced = 0;
    for (var message in pendingMessages) {
      try {
        await ApiService.instance.createMessage(message);
        synced++;
      } catch (e) {
        debugPrint('⚠️ Failed to sync message: $e');
      }
    }

    // Clear all pending messages if all synced
    if (synced == pendingMessages.length) {
      await StorageService.instance.clearPendingMessages();
    }

    return synced;
  }

  /// Get pending sync count
  Future<int> getPendingCount() async {
    return await StorageService.instance.getPendingCount();
  }

  /// Check if sync is in progress
  bool get isSyncing => _isSyncing;

  /// Force refresh cache from server
  Future<void> refreshCache() async {
    try {
      debugPrint('🔄 Refreshing cache from server...');

      // Refresh surveys
      await ApiService.instance.getSurveys();

      // Refresh FAQs
      await ApiService.instance.getFAQs();

      debugPrint('✅ Cache refreshed');
    } catch (e) {
      debugPrint('⚠️ Cache refresh failed: $e');
    }
  }
}

/// Result of sync operation
class SyncResult {
  final bool success;
  final String message;
  final int syncedLocations;
  final int syncedRespondents;
  final int syncedMessages;
  final List<String> errors;

  SyncResult({
    required this.success,
    required this.message,
    this.syncedLocations = 0,
    this.syncedRespondents = 0,
    this.syncedMessages = 0,
    this.errors = const [],
  });

  int get totalSynced => syncedLocations + syncedRespondents + syncedMessages;
}