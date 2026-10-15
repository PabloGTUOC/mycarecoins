import 'dart:convert';
import 'package:http/http.dart' as http;

/// Exception thrown by [AdminApi] on failed requests.
class AdminApiException implements Exception {
  final int statusCode;
  final String? code;
  final String message;

  AdminApiException({
    required this.statusCode,
    this.code,
    required this.message,
  });

  @override
  String toString() =>
      'AdminApiException(status: $statusCode, code: $code, message: $message)';
}

/// Abstract interface for operator console API requests.
/// Can be faked or mocked in widget tests without network or Firebase.
abstract class AdminApi {
  Future<Map<String, dynamic>> get(String path);
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]);
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body);
  Future<Map<String, dynamic>> delete(String path);
}

typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// Real HTTP implementation of [AdminApi].
/// Requests a fresh Firebase ID token per call and sends it in the Authorization header.
class HttpAdminApi implements AdminApi {
  final http.Client _client;
  final String _baseUrl;
  final TokenProvider _getToken;

  HttpAdminApi({
    required TokenProvider getToken,
    http.Client? client,
    String? baseUrl,
  })  : _getToken = getToken,
        _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? const String.fromEnvironment('API_BASE')).trim();

  Uri _buildUri(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final adminPath = cleanPath.startsWith('/admin-api')
        ? cleanPath
        : '/admin-api$cleanPath';
    return Uri.parse('$_baseUrl$adminPath');
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getToken(forceRefresh: false);
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    Map<String, dynamic>? jsonBody;
    try {
      if (response.body.isNotEmpty) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          jsonBody = decoded;
        } else if (decoded is Map) {
          jsonBody = decoded.cast<String, dynamic>();
        }
      }
    } catch (_) {
      // Body is not JSON
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonBody ?? <String, dynamic>{};
    }

    final code = jsonBody?['code']?.toString() ??
        (response.statusCode == 429
            ? 'rateLimited'
            : (response.statusCode == 404 ? 'notFound' : null));
    final message = jsonBody?['error']?.toString() ??
        jsonBody?['message']?.toString() ??
        response.reasonPhrase ??
        'HTTP ${response.statusCode}';

    throw AdminApiException(
      statusCode: response.statusCode,
      code: code,
      message: message,
    );
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    final uri = _buildUri(path);
    final headers = await _headers();
    final res = await _client.get(uri, headers: headers);
    return _handleResponse(res);
  }

  @override
  Future<Map<String, dynamic>> post(String path,
      [Map<String, dynamic>? body]) async {
    final uri = _buildUri(path);
    final headers = await _headers();
    final res = await _client.post(
      uri,
      headers: headers,
      body: body != null ? json.encode(body) : null,
    );
    return _handleResponse(res);
  }

  @override
  Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    final uri = _buildUri(path);
    final headers = await _headers();
    final res = await _client.patch(
      uri,
      headers: headers,
      body: json.encode(body),
    );
    return _handleResponse(res);
  }

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    final uri = _buildUri(path);
    final headers = await _headers();
    final res = await _client.delete(uri, headers: headers);
    return _handleResponse(res);
  }
}
