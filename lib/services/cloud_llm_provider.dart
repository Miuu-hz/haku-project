import 'package:flutter/foundation.dart';

import 'llm_provider.dart';
import 'mcp_client.dart';

/// ☁️ Cloud LLM Provider — เชื่อมต่อ Cloud LLM ผ่าน MCP/API
///
/// รองรับ 2 modes:
/// - **Tunnel mode**: ส่งผ่าน MCP endpoint (API key อยู่ที่ server)
/// - **Direct mode**: เรียก API ตรง (API key อยู่ในแอพ, สำหรับ dev)
///
/// รองรับ 3 providers:
/// - Gemini (Google) — Free tier available
/// - Claude (Anthropic) — Haiku for cost efficiency
/// - OpenAI (GPT) — GPT-4o-mini for cost efficiency

enum CloudProvider {
  gemini,
  claude,
  openai,
  openrouter,
}

enum ConnectionMode {
  tunnel, // ผ่าน MCP tunnel server
  direct, // เรียก API ตรง
}

class CloudLLMProvider implements LLMProvider {
  final CloudProvider cloudProvider;
  final MCPClient _client;
  ConnectionMode _mode;

  bool _isInitialized = false;
  bool _isLoading = false;
  int _maxTokens = 1024;

  CloudLLMProvider({
    required this.cloudProvider,
    required MCPClient client,
    ConnectionMode mode = ConnectionMode.direct,
  })  : _client = client,
        _mode = mode;

  // ── LLMProvider Interface ──

  @override
  String get providerName {
    switch (cloudProvider) {
      case CloudProvider.gemini:
        return 'Gemini Flash (Cloud)';
      case CloudProvider.claude:
        return 'Claude Haiku (Cloud)';
      case CloudProvider.openai:
        return 'GPT-4o-mini (Cloud)';
      case CloudProvider.openrouter:
        return 'OpenRouter (Cloud)';
    }
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isLoading => _isLoading;

  /// Initialize = verify connection via health check
  @override
  Future<bool> initialize({int maxTokens = 1024}) async {
    if (_isInitialized) return true;
    if (_isLoading) return false;

    _isLoading = true;
    _maxTokens = maxTokens;

    try {
      debugPrint('☁️ Initializing ${providerName}...');

      if (_mode == ConnectionMode.tunnel) {
        // Tunnel mode: health check the tunnel endpoint
        final healthy = await _client.healthCheck();
        _isInitialized = healthy;
        if (!healthy) {
          debugPrint('⚠️ Tunnel health check failed, falling back to direct');
          _mode = ConnectionMode.direct;
          _isInitialized = true; // direct mode ไม่ต้อง health check
        }
      } else {
        // Direct mode: just mark as ready
        _isInitialized = true;
      }

      _isLoading = false;

      if (_isInitialized) {
        debugPrint('✅ ${providerName} initialized (mode: ${_mode.name})');
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('❌ Cloud LLM init error: $e');
      _isLoading = false;
      return false;
    }
  }

  @override
  Future<String> generate(String prompt) async {
    if (!_isInitialized) {
      throw StateError('${providerName} not initialized');
    }

    try {
      debugPrint('☁️ Generating with ${providerName} (${_mode.name})...');

      MCPResponse response;

      if (_mode == ConnectionMode.tunnel) {
        // ส่งผ่าน MCP tunnel
        response = await _client.call('generate', {
          'prompt': prompt,
          'max_tokens': _maxTokens,
          'provider': cloudProvider.name,
        });
      } else {
        // เรียก API ตรง
        response = await _client.callDirect(
          cloudProvider.name,
          prompt,
          maxTokens: _maxTokens,
        );
      }

      if (response.success) {
        debugPrint(
            '✅ ${providerName} generated ${response.text.length} chars (${response.tokensUsed} tokens)');
        return response.text;
      } else {
        debugPrint(
            '❌ ${providerName} error: ${response.errorCode} - ${response.errorMessage}');

        // ถ้า tunnel ล้มเหลว ลอง fallback ไป direct mode
        if (_mode == ConnectionMode.tunnel) {
          debugPrint('🔄 Falling back to direct mode...');
          _mode = ConnectionMode.direct;
          return generate(prompt); // retry with direct
        }

        return '';
      }
    } catch (e) {
      debugPrint('❌ Cloud LLM generate error: $e');
      return '';
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    debugPrint('🗑️ ${providerName} disposed');
  }

  // ── Cloud-specific methods ──

  /// อัพเดท config (URL, API key, OpenRouter model)
  void updateConfig({String? baseUrl, String? apiKey, String? openRouterModel}) {
    _client.updateConfig(baseUrl: baseUrl, apiKey: apiKey, openRouterModel: openRouterModel);
  }

  /// เปลี่ยน mode
  void setMode(ConnectionMode mode) {
    _mode = mode;
  }

  /// ทดสอบ connection — throw Exception พร้อม error message ถ้าล้มเหลว
  Future<bool> testConnection() async {
    if (_mode == ConnectionMode.tunnel) {
      final healthy = await _client.healthCheck();
      if (!healthy) {
        throw Exception('Tunnel endpoint ไม่ตอบ: ${_client.baseUrl}');
      }
      return true;
    }

    // Direct mode: ส่ง simple prompt ทดสอบ
    final response = await _client.callDirect(
      cloudProvider.name,
      'Hello, respond with just "OK"',
      maxTokens: 10,
    );
    if (!response.success) {
      throw Exception(response.errorMessage ?? 'Unknown error');
    }
    return true;
  }

  /// ดึง connection info
  Map<String, dynamic> getConnectionInfo() => {
        'provider': cloudProvider.name,
        'providerName': providerName,
        'mode': _mode.name,
        'baseUrl': _client.baseUrl,
        'isInitialized': _isInitialized,
      };
}
