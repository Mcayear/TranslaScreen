import 'package:shared_preferences/shared_preferences.dart';

enum OcrEngineType { local, openai }

class SettingsService {
  static const String _keySelectedOcrEngine = 'selected_ocr_engine';
  static const String _keyOpenAiApiKey = 'openai_api_key';
  static const String _keyOpenAiApiEndpoint = 'openai_api_endpoint';
  static const String _keyOpenAiModelName = 'openai_model_name';

  // Default values
  static const String defaultOpenAiEndpoint =
      'https://api.openai.com/v1/chat/completions';
  static const String defaultOpenAiModel =
      'gpt-4-vision-preview'; // Or 'gpt-4o', 'gpt-4-turbo'

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  // --- OCR Engine Selection ---
  Future<void> setSelectedOcrEngine(OcrEngineType engineType) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keySelectedOcrEngine, engineType.name);
  }

  Future<OcrEngineType> getSelectedOcrEngine() async {
    final prefs = await _getPrefs();
    final String? engineName = prefs.getString(_keySelectedOcrEngine);
    if (engineName == OcrEngineType.openai.name) {
      return OcrEngineType.openai;
    }
    return OcrEngineType.local; // Default to local
  }

  // --- OpenAI API Key ---
  Future<void> setOpenAiApiKey(String apiKey) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyOpenAiApiKey, apiKey);
  }

  Future<String?> getOpenAiApiKey() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyOpenAiApiKey);
  }

  // --- OpenAI API Endpoint ---
  Future<void> setOpenAiApiEndpoint(String endpoint) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyOpenAiApiEndpoint, endpoint);
  }

  Future<String> getOpenAiApiEndpoint() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyOpenAiApiEndpoint) ?? defaultOpenAiEndpoint;
  }

  // --- OpenAI Model Name ---
  Future<void> setOpenAiModelName(String modelName) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyOpenAiModelName, modelName);
  }

  Future<String> getOpenAiModelName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyOpenAiModelName) ?? defaultOpenAiModel;
  }

  // --- Utility to get all OpenAI config ---
  Future<Map<String, String>> getOpenAiConfig() async {
    return {
      'apiKey': await getOpenAiApiKey() ?? '',
      'apiEndpoint': await getOpenAiApiEndpoint(),
      'modelName': await getOpenAiModelName(),
    };
  }
}
