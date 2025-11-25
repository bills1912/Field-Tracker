import 'api_service.dart';
import 'storage_service.dart';

class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();
  
  SyncService._();

  bool _isSyncing = false;

  Future<void> syncAll() async {
    if (_isSyncing) return;

    _isSyncing = true;

    try {
      // Sync locations
      await _syncLocations();

      // Sync respondents
      await _syncRespondents();

      // Sync messages
      await _syncMessages();
    } catch (e) {
      print('Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncLocations() async {
    final pendingLocations = await StorageService.instance.getPendingLocations();
    
    if (pendingLocations.isEmpty) return;

    try {
      await ApiService.instance.createLocationsBatch(pendingLocations);
      await StorageService.instance.clearPendingLocations();
    } catch (e) {
      print('Location sync error: $e');
    }
  }

  Future<void> _syncRespondents() async {
    final pendingRespondents = await StorageService.instance.getPendingRespondents();
    
    if (pendingRespondents.isEmpty) return;

    for (var respondent in pendingRespondents) {
      try {
        await ApiService.instance.createRespondent(respondent.toJson());
      } catch (e) {
        print('Respondent sync error: $e');
      }
    }

    await StorageService.instance.clearPendingRespondents();
  }

  Future<void> _syncMessages() async {
    final pendingMessages = await StorageService.instance.getPendingMessages();
    
    if (pendingMessages.isEmpty) return;

    for (var message in pendingMessages) {
      try {
        await ApiService.instance.createMessage(message);
      } catch (e) {
        print('Message sync error: $e');
      }
    }

    await StorageService.instance.clearPendingMessages();
  }
}