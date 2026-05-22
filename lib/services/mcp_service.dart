import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 🔌 MCP Service — Model Context Protocol Client
///
/// เชื่อมต่อกับ MCP server (JSON-RPC 2.0 over HTTP POST)
/// - `connect()` — handshake + list tools
/// - `callTool()` — เรียก tool โดยตรง
/// - `search()` — ค้นหาอัตโนมัติ: brave_search → web_search → search → fallback
///
/// URL เก็บใน SharedPreferences (key: `mcp_server_url`)

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> j) => McpTool(
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        inputSchema: j['inputSchema'] as Map<String, dynamic>? ?? {},
      );
}

class McpService {
  static final McpService _instance = McpService._internal();
  factory McpService() => _instance;
  McpService._internal();

  static const _prefKey = 'mcp_server_url';
  String? _serverUrl;
  List<McpTool> _tools = [];
  int _idCounter = 1;

  bool get isConfigured => _serverUrl != null && _serverUrl!.isNotEmpty;
  String? get serverUrl => _serverUrl;
  List<McpTool> get tools => List.unmodifiable(_tools);

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_prefKey);
  }

  Future<void> saveServerUrl(String url) async {
    _serverUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _serverUrl!);
  }

  /// เชื่อมต่อ MCP server: handshake + list tools
  Future<bool> connect() async {
    if (!isConfigured) return false;
    try {
      await _sendRequest('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'haku', 'version': '1.0.0'},
      });
      final result = await _sendRequest('tools/list', <String, dynamic>{});
      final toolList = result['tools'] as List<dynamic>? ?? [];
      _tools = toolList
          .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
          .toList();
      debugPrint('🔌 MCP connected: ${_tools.length} tools');
      return true;
    } catch (e) {
      debugPrint('❌ MCP connect failed: $e');
      return false;
    }
  }

  /// เรียก MCP tool โดยตรง → คืน text result
  Future<String?> callTool(
      String toolName, Map<String, dynamic> arguments) async {
    if (!isConfigured) return null;
    try {
      final result = await _sendRequest('tools/call', {
        'name': toolName,
        'arguments': arguments,
      });
      final content = result['content'] as List<dynamic>?;
      if (content != null && content.isNotEmpty) {
        return content
            .where((c) => (c as Map)['type'] == 'text')
            .map((c) => (c as Map)['text'] as String)
            .join('\n');
      }
      return null;
    } catch (e) {
      debugPrint('❌ MCP callTool failed: $e');
      return null;
    }
  }

  /// ค้นหาด้วย MCP — ลอง brave_search → web_search → search → tool แรกที่มี "search"
  Future<String?> search(String query) async {
    if (!isConfigured) return null;
    for (final name in ['brave_search', 'web_search', 'search']) {
      if (_tools.any((t) => t.name == name)) {
        return callTool(name, {'query': query});
      }
    }
    try {
      final fallback = _tools.firstWhere((t) => t.name.contains('search'));
      return callTool(fallback.name, {'query': query});
    } catch (_) {
      debugPrint('❌ MCP: no search tool available');
      return null;
    }
  }

  Future<Map<String, dynamic>> _sendRequest(
      String method, Map<String, dynamic> params) async {
    final id = _idCounter++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'id': id,
      'params': params,
    });
    final response = await http
        .post(
          Uri.parse(_serverUrl!),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('MCP HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception('MCP error: ${json['error']}');
    }
    return json['result'] as Map<String, dynamic>? ?? {};
  }
}
