import 'package:flutter/foundation.dart';
import '../models/survey.dart';
import '../models/user.dart';
import '../models/survey_stats.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class SurveyProvider with ChangeNotifier {
  Survey? _selectedSurvey;
  List<Survey> _surveys = [];
  Map<String, SurveyStats> _surveyStats = {};
  Set<String> _pinnedSurveyIds = {};
  bool _isLoading = false;

  Survey? get selectedSurvey => _selectedSurvey;
  String? get selectedSurveyId => _selectedSurvey?.id;
  List<Survey> get surveys => _surveys;
  Map<String, SurveyStats> get surveyStats => _surveyStats;
  bool get isLoading => _isLoading;

  /// Get only pinned surveys
  List<Survey> get pinnedSurveys {
    return _surveys.where((survey) => _pinnedSurveyIds.contains(survey.id)).toList();
  }

  /// Check if a survey is pinned
  bool isPinned(String surveyId) {
    return _pinnedSurveyIds.contains(surveyId);
  }

  SurveyProvider() {
    _loadSelectedSurvey();
    _loadPinnedSurveys();
  }

  /// Load selected survey from storage
  Future<void> _loadSelectedSurvey() async {
    final surveyData = await StorageService.instance.getSelectedSurveyData();
    if (surveyData != null) {
      _selectedSurvey = Survey.fromJson(surveyData);
      notifyListeners();
    }
  }

  /// Load pinned surveys from storage
  Future<void> _loadPinnedSurveys() async {
    _pinnedSurveyIds = await StorageService.instance.getPinnedSurveys();
    notifyListeners();
  }

  /// Set selected survey
  Future<void> setSelectedSurvey(Survey? survey) async {
    _selectedSurvey = survey;

    if (survey != null) {
      await StorageService.instance.saveSelectedSurvey(
        survey.id,
        survey.toJson(),
      );
    } else {
      await StorageService.instance.clearSelectedSurvey();
    }

    notifyListeners();
  }

  /// Toggle pin status of a survey
  Future<void> togglePinSurvey(String surveyId) async {
    if (_pinnedSurveyIds.contains(surveyId)) {
      _pinnedSurveyIds.remove(surveyId);
    } else {
      _pinnedSurveyIds.add(surveyId);
    }

    // Save to storage
    await StorageService.instance.savePinnedSurveys(_pinnedSurveyIds);
    notifyListeners();
  }

  /// Pin a survey
  Future<void> pinSurvey(String surveyId) async {
    if (!_pinnedSurveyIds.contains(surveyId)) {
      _pinnedSurveyIds.add(surveyId);
      await StorageService.instance.savePinnedSurveys(_pinnedSurveyIds);
      notifyListeners();
    }
  }

  /// Unpin a survey
  Future<void> unpinSurvey(String surveyId) async {
    if (_pinnedSurveyIds.contains(surveyId)) {
      _pinnedSurveyIds.remove(surveyId);
      await StorageService.instance.savePinnedSurveys(_pinnedSurveyIds);
      notifyListeners();
    }
  }

  /// Load all surveys from API
  Future<void> loadSurveys() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Ambil semua survei mentah dari API
      final rawSurveys = await ApiService.instance.getSurveys();

      // 2. Ambil user yang sedang login untuk pengecekan role & ID
      final user = await StorageService.instance.getUser();

      // 3. Lakukan Filtering
      if (user != null) {
        if (user.role == UserRole.admin) {
          // Admin melihat semua survei
          _surveys = rawSurveys;
        } else {
          // Filter untuk Supervisor dan Enumerator
          _surveys = rawSurveys.where((survey) {
            if (user.role == UserRole.supervisor) {
              return survey.supervisorIds.contains(user.id);
            } else {
              // Enumerator: Hanya jika ID mereka ada di list enumerator
              return survey.enumeratorIds.contains(user.id);
            }
          }).toList();
        }
      } else {
        // Fallback jika user null (misal session expired)
        _surveys = [];
      }

      // Load stats for each survey
      for (var survey in _surveys) {
        try {
          final stats = await ApiService.instance.getSurveyStats(survey.id);
          _surveyStats[survey.id] = stats;
        } catch (e) {
          print('Error loading stats for survey ${survey.id}: $e');
        }
      }
    } catch (e) {
      print('Error loading surveys: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh survey stats for a specific survey
  Future<void> refreshSurveyStats(String surveyId) async {
    try {
      final stats = await ApiService.instance.getSurveyStats(surveyId);
      _surveyStats[surveyId] = stats;
      notifyListeners();
    } catch (e) {
      print('Error refreshing survey stats: $e');
    }
  }
}