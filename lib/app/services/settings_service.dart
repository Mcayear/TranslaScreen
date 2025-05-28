import 'package:shared_preferences/shared_preferences.dart';
import 'package:transla_screen/app/core/constants/enums.dart'; // Updated import

class SettingsService {
  static const String _keySelectedOcrEngine = 'selected_ocr_engine';
  static const String _keyOpenAiApiKey = 'openai_api_key';
  static const String _keyOpenAiApiEndpoint = 'openai_api_endpoint';
  static const String _keyOpenAiModelName = 'openai_model_name';

  // New keys for OpenAI Translation
  static const String _keyOpenAiTranslationApiKey =
      'openai_translation_api_key';
  static const String _keyOpenAiTranslationApiEndpoint =
      'openai_translation_api_endpoint';
  static const String _keyOpenAiTranslationModelName =
      'openai_translation_model_name';

  // Default values
  static const String defaultOpenAiEndpoint =
      'https://api.openai.com/v1/chat/completions';
  static const String defaultOpenAiModel =
      'gpt-4-vision-preview'; // Or 'gpt-4o', 'gpt-4-turbo'
  // Default for translation
  static const String defaultOpenAiTranslationModel = 'gpt-3.5-turbo';

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

  // --- OpenAI Translation API Key ---
  Future<void> setOpenAiTranslationApiKey(String apiKey) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyOpenAiTranslationApiKey, apiKey);
  }

  Future<String?> getOpenAiTranslationApiKey() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyOpenAiTranslationApiKey);
  }

  // --- OpenAI Translation API Endpoint ---
  Future<void> setOpenAiTranslationApiEndpoint(String endpoint) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyOpenAiTranslationApiEndpoint, endpoint);
  }

  Future<String> getOpenAiTranslationApiEndpoint() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyOpenAiTranslationApiEndpoint) ??
        defaultOpenAiEndpoint; // Can use same default endpoint
  }

  // --- OpenAI Translation Model Name ---
  Future<void> setOpenAiTranslationModelName(String modelName) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyOpenAiTranslationModelName, modelName);
  }

  Future<String> getOpenAiTranslationModelName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyOpenAiTranslationModelName) ??
        defaultOpenAiTranslationModel;
  }

  // --- Utility to get all OpenAI Translation config ---
  Future<Map<String, String>> getOpenAiTranslationConfig() async {
    return {
      'apiKey': await getOpenAiTranslationApiKey() ?? '',
      'apiEndpoint': await getOpenAiTranslationApiEndpoint(),
      'modelName': await getOpenAiTranslationModelName(),
    };
  }
}
