import 'package:flutter/foundation.dart';
import '../models/survey.dart';
import '../models/survey_stats.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class SurveyProvider with ChangeNotifier {
  Survey? _selectedSurvey;
  List<Survey> _surveys = [];
  Map<String, SurveyStats> _surveyStats = {};
  bool _isLoading = false;

  Survey? get selectedSurvey => _selectedSurvey;
  String? get selectedSurveyId => _selectedSurvey?.id;
  List<Survey> get surveys => _surveys;
  Map<String, SurveyStats> get surveyStats => _surveyStats;
  bool get isLoading => _isLoading;

  SurveyProvider() {
    _loadSelectedSurvey();
  }

  Future<void> _loadSelectedSurvey() async {
    final surveyData = await StorageService.instance.getSelectedSurveyData();
    if (surveyData != null) {
      _selectedSurvey = Survey.fromJson(surveyData);
      notifyListeners();
    }
  }

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

  Future<void> loadSurveys() async {
    _isLoading = true;
    notifyListeners();

    try {
      _surveys = await ApiService.instance.getSurveys();
      
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