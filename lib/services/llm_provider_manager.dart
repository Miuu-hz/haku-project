import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_llm_provider.dart';
import 'llm_provider.dart';
import 'mcp_client.dart';
import 'mediapipe_llm_provider.dart';

/// 🎛️ LLM Provider Manager — Provider Switching + Fallback
///
/// Singleton ที่จัดการ active LLM provider:
/// - สลับระหว่าง On-device / Cloud providers
/// - Auto-fallback chain: Cloud → SLM → Mock
/// - บันทึก preference ใน SharedPreferences
/// - เก็บ API config (endpoint, key)

enum ProviderType {
  onDevice,
  cloudGemini,
  cloudClaude,
  cloudOpenai,
}

class LLMProviderManager {
  static final LLMProviderManager _instance = LLMProviderManager._internal();
  factory LLMProviderManager() => _instance;
  LLMProviderManager._internal();

  // ── Storage Keys ──
  static const String _prefProviderType = 'llm_provider_type';
  static const String _prefApiEndpoint = 'llm_api_endpoint';
  static const String _prefApiKey = 'llm_api_key';
  static const String _prefConnectionMode = 'llm_connection_mode';

  // ── State ──
  ProviderType _activeType = ProviderType.onDevice;
  LLMProvider? _activeProvider;
  bool _isInitialized = false;

  // ── Provider instances (lazy) ──
  MediaPipeLLMProvider? _mediaPipeProvider;
  CloudLLMProvider? _geminiProvider;
  CloudLLMProvider? _claudeProvider;
  CloudLLMProvider? _openaiProvider;
  final MockLLMProvider _mockProvider = MockLLMProvider();

  // ── Shared MCP client ──
  MCPClient? _mcpClient;

  // ── Public API ──

  /// Active LLM provider
  LLMProvider get provider => _activeProvider ?? _mockProvider;

  /// Active provider type
  ProviderType get activeType => _activeType;

  /// Provider name สำหรับ UI
  String get providerName => provider.providerName;

  /// Whether manager has been initialized
  bool get isManagerInitialized => _isInitialized;

  /// 🚀 Initialize — load saved preference and create provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load saved config
      final typeIndex = prefs.getInt(_prefProviderType) ?? 0;
      _activeType = ProviderType.values[typeIndex.clamp(0, ProviderType.values.length - 1)];

      final endpoint = prefs.getString(_prefApiEndpoint) ?? '';
      final apiKey = prefs.getString(_prefApiKey) ?? '';
      final modeIndex = prefs.getInt(_prefConnectionMode) ?? 1; // default direct
      final mode = ConnectionMode.values[modeIndex.clamp(0, ConnectionMode.values.length - 1)];

      // Create MCP client if we have endpoint/key
      if (endpoint.isNotEmpty || apiKey.isNotEmpty) {
        _mcpClient = MCPClient(
          baseUrl: endpoint.isNotEmpty ? endpoint : 'http://localhost:3000',
          apiKey: apiKey.isNotEmpty ? apiKey : null,
        );
      }

      // Create the active provider
      _activeProvider = _createProvider(_activeType, mode: mode);

      _isInitialized = true;
      debugPrint('🎛️ LLM Provider Manager initialized');
      debugPrint('   - Type: ${_activeType.name}');
      debugPrint('   - Provider: ${provider.providerName}');
    } catch (e) {
      debugPrint('⚠️ LLM Provider Manager init failed: $e');
      // Fallback to on-device
      _activeType = ProviderType.onDevice;
      _activeProvider = _getMediaPipeProvider();
      _isInitialized = true;
    }
  }

  /// 🔄 Switch to a different provider
  Future<bool> switchProvider(
    ProviderType type, {
    String? apiEndpoint,
    String? apiKey,
    ConnectionMode mode = ConnectionMode.direct,
  }) async {
    debugPrint('🔄 Switching to ${type.name}...');

    // Update config if provided
    if (apiEndpoint != null || apiKey != null) {
      _mcpClient = MCPClient(
        baseUrl: apiEndpoint ?? _mcpClient?.baseUrl ?? 'http://localhost:3000',
        apiKey: apiKey ?? '',
      );
    }

    // Dispose current provider if switching to different type
    if (type != _activeType && _activeProvider != null) {
      await _activeProvider!.dispose();
    }

    // Create new provider
    _activeProvider = _createProvider(type, mode: mode);
    _activeType = type;

    // Save preference
    await _savePreference(type, apiEndpoint, apiKey, mode);

    debugPrint('✅ Switched to ${provider.providerName}');
    return true;
  }

  /// 🏥 Test connection for a provider type
  Future<bool> testConnection(
    ProviderType type, {
    String? apiEndpoint,
    String? apiKey,
    ConnectionMode mode = ConnectionMode.direct,
  }) async {
    if (type == ProviderType.onDevice) {
      // On-device: check if model file exists
      final mp = _getMediaPipeProvider();
      final validation = await mp.validateCustomModel();
      return validation['valid'] == true;
    }

    // Cloud: create temporary client and test
    final client = MCPClient(
      baseUrl: apiEndpoint ?? _mcpClient?.baseUrl ?? '',
      apiKey: apiKey,
    );

    final cloudType = _providerTypeToCloud(type);
    if (cloudType == null) return false;

    final tempProvider = CloudLLMProvider(
      cloudProvider: cloudType,
      client: client,
      mode: mode,
    );

    return tempProvider.testConnection();
  }

  /// 📋 Get all available provider types with info
  List<ProviderInfo> getAvailableProviders() => [
        ProviderInfo(
          type: ProviderType.onDevice,
          name: 'On-device (Gemma 3 1B)',
          description: 'ฟรี, ออฟไลน์, ช้ากว่า Cloud',
          icon: '📱',
          requiresApiKey: false,
        ),
        ProviderInfo(
          type: ProviderType.cloudGemini,
          name: 'Gemini Flash (Google)',
          description: 'Free tier, เร็ว, context 1M tokens',
          icon: '🔵',
          requiresApiKey: true,
        ),
        ProviderInfo(
          type: ProviderType.cloudClaude,
          name: 'Claude Haiku (Anthropic)',
          description: '\$0.25/1M tokens, ฉลาด, context 200K',
          icon: '🟣',
          requiresApiKey: true,
        ),
        ProviderInfo(
          type: ProviderType.cloudOpenai,
          name: 'GPT-4o-mini (OpenAI)',
          description: '\$0.15/1M tokens, เร็ว, context 128K',
          icon: '🟢',
          requiresApiKey: true,
        ),
      ];

  /// 📊 Get current config
  Future<Map<String, dynamic>> getCurrentConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'providerType': _activeType.name,
      'providerName': provider.providerName,
      'apiEndpoint': prefs.getString(_prefApiEndpoint) ?? '',
      'hasApiKey': (prefs.getString(_prefApiKey) ?? '').isNotEmpty,
      'connectionMode': prefs.getInt(_prefConnectionMode) == 0
          ? 'tunnel'
          : 'direct',
      'isInitialized': provider.isInitialized,
    };
  }

  // ── Internal ──

  LLMProvider _createProvider(ProviderType type, {ConnectionMode mode = ConnectionMode.direct}) {
    switch (type) {
      case ProviderType.onDevice:
        return _getMediaPipeProvider();

      case ProviderType.cloudGemini:
        _geminiProvider ??= CloudLLMProvider(
          cloudProvider: CloudProvider.gemini,
          client: _getOrCreateMCPClient(),
          mode: mode,
        );
        return _geminiProvider!;

      case ProviderType.cloudClaude:
        _claudeProvider ??= CloudLLMProvider(
          cloudProvider: CloudProvider.claude,
          client: _getOrCreateMCPClient(),
          mode: mode,
        );
        return _claudeProvider!;

      case ProviderType.cloudOpenai:
        _openaiProvider ??= CloudLLMProvider(
          cloudProvider: CloudProvider.openai,
          client: _getOrCreateMCPClient(),
          mode: mode,
        );
        return _openaiProvider!;
    }
  }

  MediaPipeLLMProvider _getMediaPipeProvider() {
    _mediaPipeProvider ??= MediaPipeLLMProvider();
    return _mediaPipeProvider!;
  }

  MCPClient _getOrCreateMCPClient() {
    _mcpClient ??= MCPClient(
      baseUrl: 'http://localhost:3000',
    );
    return _mcpClient!;
  }

  CloudProvider? _providerTypeToCloud(ProviderType type) {
    switch (type) {
      case ProviderType.cloudGemini:
        return CloudProvider.gemini;
      case ProviderType.cloudClaude:
        return CloudProvider.claude;
      case ProviderType.cloudOpenai:
        return CloudProvider.openai;
      case ProviderType.onDevice:
        return null;
    }
  }

  Future<void> _savePreference(
    ProviderType type,
    String? endpoint,
    String? apiKey,
    ConnectionMode mode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefProviderType, type.index);
    if (endpoint != null) {
      await prefs.setString(_prefApiEndpoint, endpoint);
    }
    if (apiKey != null) {
      await prefs.setString(_prefApiKey, apiKey);
    }
    await prefs.setInt(_prefConnectionMode, mode.index);
  }
}

/// 📋 Provider Info for UI
class ProviderInfo {
  final ProviderType type;
  final String name;
  final String description;
  final String icon;
  final bool requiresApiKey;

  const ProviderInfo({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.requiresApiKey,
  });
}
