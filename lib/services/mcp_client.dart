import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 🔌 MCP Client — Model Context Protocol Client
///
/// Lightweight JSON-based protocol สำหรับสื่อสารระหว่าง Flutter app กับ LLM API tunnel
///
/// Protocol:
/// ```json
/// // Request
/// { "method": "generate", "params": { "prompt": "...", "max_tokens": 512, "provider": "gemini" } }
///
/// // Response
/// { "result": { "text": "...", "provider": "gemini", "tokens_used": 150 } }
///
/// // Error
/// { "error": { "code": 429, "message": "Rate limit exceeded" } }
/// ```

class MCPClient {
  String _baseUrl;
  String? _apiKey;
  final Duration _timeout;
  final int _maxRetries;

  MCPClient({
    required String baseUrl,
    String? apiKey,
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 3,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _apiKey = apiKey,
        _timeout = timeout,
        _maxRetries = maxRetries;

  // ── Configuration ──

  String get baseUrl => _baseUrl;

  void updateConfig({String? baseUrl, String? apiKey}) {
    if (baseUrl != null) {
      _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    }
    if (apiKey != null) {
      _apiKey = apiKey;
    }
  }

  // ── Core Protocol ──

  /// 📡 Send MCP request to tunnel
  Future<MCPResponse> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    final body = jsonEncode({
      'method': method,
      'params': params,
    });

    Exception? lastError;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          // Exponential backoff: 1s, 2s, 4s
          final delay = Duration(seconds: 1 << (attempt - 1));
          debugPrint('🔄 MCP retry $attempt after ${delay.inSeconds}s...');
          await Future.delayed(delay);
        }

        final response = await http
            .post(
              Uri.parse('$_baseUrl/mcp'),
              headers: {
                'Content-Type': 'application/json',
                if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
              },
              body: body,
            )
            .timeout(_timeout);

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;

          if (json.containsKey('error')) {
            final error = json['error'] as Map<String, dynamic>;
            return MCPResponse.error(
              code: error['code'] as int? ?? -1,
              message: error['message'] as String? ?? 'Unknown error',
            );
          }

          final result = json['result'] as Map<String, dynamic>? ?? {};
          return MCPResponse.success(
            text: result['text'] as String? ?? '',
            provider: result['provider'] as String? ?? 'unknown',
            tokensUsed: result['tokens_used'] as int? ?? 0,
          );
        }

        // HTTP errors
        if (response.statusCode == 429) {
          lastError = MCPException('Rate limit exceeded', response.statusCode);
          continue; // retry
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          return MCPResponse.error(
            code: response.statusCode,
            message: 'Authentication failed. Check API key.',
          );
        }

        if (response.statusCode >= 500) {
          lastError = MCPException(
              'Server error: ${response.statusCode}', response.statusCode);
          continue; // retry
        }

        return MCPResponse.error(
          code: response.statusCode,
          message: 'HTTP ${response.statusCode}: ${response.body}',
        );
      } on TimeoutException {
        lastError = MCPException('Request timed out', 408);
        continue; // retry
      } catch (e) {
        lastError = MCPException('Connection failed: $e', -1);
        continue; // retry
      }
    }

    return MCPResponse.error(
      code: -1,
      message: 'All retries failed: ${lastError?.toString() ?? "Unknown error"}',
    );
  }

  // ── Direct API Calls (no tunnel) ──

  /// 📡 Call provider API directly (for dev mode)
  Future<MCPResponse> callDirect(
    String provider,
    String prompt, {
    int maxTokens = 1024,
  }) async {
    switch (provider) {
      case 'gemini':
        return _callGemini(prompt, maxTokens);
      case 'claude':
        return _callClaude(prompt, maxTokens);
      case 'openai':
        return _callOpenAI(prompt, maxTokens);
      default:
        return MCPResponse.error(
          code: -1,
          message: 'Unknown provider: $provider',
        );
    }
  }

  /// 🔵 Gemini API (Google)
  Future<MCPResponse> _callGemini(String prompt, int maxTokens) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return MCPResponse.error(code: 401, message: 'Gemini API key required');
    }

    try {
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey';

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'maxOutputTokens': maxTokens,
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content =
              candidates[0]['content'] as Map<String, dynamic>? ?? {};
          final parts = content['parts'] as List? ?? [];
          if (parts.isNotEmpty) {
            final text = parts[0]['text'] as String? ?? '';
            final meta = json['usageMetadata'] as Map<String, dynamic>? ?? {};
            return MCPResponse.success(
              text: text,
              provider: 'gemini',
              tokensUsed: meta['totalTokenCount'] as int? ?? 0,
            );
          }
        }
        return MCPResponse.error(
            code: -1, message: 'Empty response from Gemini');
      }

      return MCPResponse.error(
        code: response.statusCode,
        message: 'Gemini API error: ${response.body}',
      );
    } catch (e) {
      return MCPResponse.error(code: -1, message: 'Gemini API failed: $e');
    }
  }

  /// 🟣 Claude API (Anthropic)
  Future<MCPResponse> _callClaude(String prompt, int maxTokens) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return MCPResponse.error(code: 401, message: 'Claude API key required');
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': _apiKey!,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': 'claude-haiku-4-5-20251001',
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final content = json['content'] as List? ?? [];
        if (content.isNotEmpty) {
          final text = content[0]['text'] as String? ?? '';
          final usage = json['usage'] as Map<String, dynamic>? ?? {};
          final inputTokens = usage['input_tokens'] as int? ?? 0;
          final outputTokens = usage['output_tokens'] as int? ?? 0;
          return MCPResponse.success(
            text: text,
            provider: 'claude',
            tokensUsed: inputTokens + outputTokens,
          );
        }
        return MCPResponse.error(
            code: -1, message: 'Empty response from Claude');
      }

      return MCPResponse.error(
        code: response.statusCode,
        message: 'Claude API error: ${response.body}',
      );
    } catch (e) {
      return MCPResponse.error(code: -1, message: 'Claude API failed: $e');
    }
  }

  /// 🟢 OpenAI API
  Future<MCPResponse> _callOpenAI(String prompt, int maxTokens) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return MCPResponse.error(code: 401, message: 'OpenAI API key required');
    }

    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = json['choices'] as List? ?? [];
        if (choices.isNotEmpty) {
          final message =
              choices[0]['message'] as Map<String, dynamic>? ?? {};
          final text = message['content'] as String? ?? '';
          final usage = json['usage'] as Map<String, dynamic>? ?? {};
          return MCPResponse.success(
            text: text,
            provider: 'openai',
            tokensUsed: usage['total_tokens'] as int? ?? 0,
          );
        }
        return MCPResponse.error(
            code: -1, message: 'Empty response from OpenAI');
      }

      return MCPResponse.error(
        code: response.statusCode,
        message: 'OpenAI API error: ${response.body}',
      );
    } catch (e) {
      return MCPResponse.error(code: -1, message: 'OpenAI API failed: $e');
    }
  }

  // ── Health Check ──

  /// 🏥 Check if tunnel/API is reachable
  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/health'),
            headers: {
              if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
            },
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ MCP health check failed: $e');
      return false;
    }
  }
}

// ── Data Models ──

/// 📦 MCP Response
class MCPResponse {
  final bool success;
  final String text;
  final String provider;
  final int tokensUsed;
  final int? errorCode;
  final String? errorMessage;

  MCPResponse._({
    required this.success,
    this.text = '',
    this.provider = '',
    this.tokensUsed = 0,
    this.errorCode,
    this.errorMessage,
  });

  factory MCPResponse.success({
    required String text,
    required String provider,
    int tokensUsed = 0,
  }) =>
      MCPResponse._(
        success: true,
        text: text,
        provider: provider,
        tokensUsed: tokensUsed,
      );

  factory MCPResponse.error({required int code, required String message}) =>
      MCPResponse._(
        success: false,
        errorCode: code,
        errorMessage: message,
      );
}

/// ❌ MCP Exception
class MCPException implements Exception {
  final String message;
  final int statusCode;

  MCPException(this.message, this.statusCode);

  @override
  String toString() => 'MCPException($statusCode): $message';
}
