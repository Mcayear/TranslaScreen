import 'package:flutter/material.dart';
import 'package:transla_screen/services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();
  OcrEngineType _selectedEngine = OcrEngineType.local;
  final _apiKeyController = TextEditingController();
  final _apiEndpointController = TextEditingController();
  final _modelNameController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    _selectedEngine = await _settingsService.getSelectedOcrEngine();
    _apiKeyController.text = await _settingsService.getOpenAiApiKey() ?? '';
    _apiEndpointController.text = await _settingsService.getOpenAiApiEndpoint();
    _modelNameController.text = await _settingsService.getOpenAiModelName();
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    await _settingsService.setSelectedOcrEngine(_selectedEngine);
    if (_selectedEngine == OcrEngineType.openai) {
      await _settingsService.setOpenAiApiKey(_apiKeyController.text.trim());
      await _settingsService
          .setOpenAiApiEndpoint(_apiEndpointController.text.trim());
      await _settingsService
          .setOpenAiModelName(_modelNameController.text.trim());
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存!')),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiEndpointController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: <Widget>[
                const Text('OCR 引擎选择',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                RadioListTile<OcrEngineType>(
                  title: const Text('本地 OCR (ML Kit)'),
                  value: OcrEngineType.local,
                  groupValue: _selectedEngine,
                  onChanged: (OcrEngineType? value) {
                    if (value != null) {
                      setState(() {
                        _selectedEngine = value;
                      });
                    }
                  },
                ),
                RadioListTile<OcrEngineType>(
                  title: const Text('云端 OCR (OpenAI)'),
                  value: OcrEngineType.openai,
                  groupValue: _selectedEngine,
                  onChanged: (OcrEngineType? value) {
                    if (value != null) {
                      setState(() {
                        _selectedEngine = value;
                      });
                    }
                  },
                ),
                if (_selectedEngine == OcrEngineType.openai) ...[
                  const SizedBox(height: 20),
                  const Text('OpenAI API 配置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'OpenAI API Key',
                      border: OutlineInputBorder(),
                      hintText: 'sk-xxxxxxxxxxxx',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiEndpointController,
                    decoration: const InputDecoration(
                      labelText: 'OpenAI API Endpoint URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _modelNameController,
                    decoration: const InputDecoration(
                      labelText: 'OpenAI Model Name',
                      border: OutlineInputBorder(),
                      hintText: 'gpt-4-vision-preview or gpt-4o etc.',
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('保存设置'),
                ),
              ],
            ),
    );
  }
}
