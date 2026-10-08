import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Categorizes a client-side request failure so the message can be localized
/// at the display boundary (AppState holds the current AppLocalizations).
/// [server] carries a backend-authored message, which is passed through as-is.
enum ApiErrorKind {
  timeout,
  network,
  requestFailed,
  uploadTimeout,
  uploadFailed,
  server,
}

class ApiException implements Exception {
  final ApiErrorKind kind;
  final int? statusCode;

  /// Backend-provided message (already human-readable); only set for
  /// [ApiErrorKind.server]. Not localizable client-side.
  final String? serverMessage;

  ApiException(this.kind, {this.statusCode, this.serverMessage});

  /// English fallback for logs and any caller without an AppLocalizations.
  @override
  String toString() =>
      serverMessage ??
      switch (kind) {
        ApiErrorKind.timeout => 'Request timed out; check your connection.',
        ApiErrorKind.network => 'Network error; check your connection.',
        ApiErrorKind.requestFailed => 'Request failed (${statusCode ?? 0})',
        ApiErrorKind.uploadTimeout => 'Upload timed out',
        ApiErrorKind.uploadFailed => 'Upload failed (${statusCode ?? 0})',
        ApiErrorKind.server => 'Request failed',
      };
}

/// Thin REST client:
/// JSON in/out, Bearer token, 10s timeout, error message from `data.error`.
class ApiClient {
  /// Override at build time: flutter run --dart-define=API_BASE=http://192.168.1.10:3000
  /// (Android emulators reach the host machine via http://10.0.2.2:3000.)
  static const String apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3000');

  String token = '';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> request(String path,
      {String method = 'GET', Object? body}) async {
    final uri = Uri.parse('$apiBase$path');
    final client = http.Client();
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 20));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(ApiErrorKind.timeout);
    } on http.ClientException {
      // http wraps SocketException & co.; surface a human message instead
      // of "ClientException with SocketException: Failed host lookup…".
      throw ApiException(ApiErrorKind.network);
    } finally {
      client.close();
    }

    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = <String, dynamic>{};
    }
    if (res.statusCode >= 400) {
      if (data is Map && data['error'] != null) {
        // Carry the status code even though the message came from the
        // backend: callers need to tell "your session is gone" (401/403)
        // apart from any other refusal.
        throw ApiException(ApiErrorKind.server,
            statusCode: res.statusCode,
            serverMessage: data['error'].toString());
      }
      throw ApiException(ApiErrorKind.requestFailed, statusCode: res.statusCode);
    }
    return data;
  }

  /// Multipart upload (avatar endpoints): auth header only, no JSON content
  /// type.
  /// [contentType] must be given for anything the server type-checks: without
  /// it the http package labels the part `application/octet-stream`, and a
  /// multer `fileFilter` reading `file.mimetype` rejects the upload outright.
  Future<dynamic> uploadFile(String path,
      {required String field,
      required List<int> bytes,
      required String filename,
      String? contentType}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiBase$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes(field, bytes,
          filename: filename.isEmpty ? 'avatar.jpg' : filename,
          contentType:
              contentType == null ? null : MediaType.parse(contentType)));
    http.Response res;
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(ApiErrorKind.uploadTimeout);
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = <String, dynamic>{};
    }
    if (res.statusCode >= 400) {
      if (data is Map && data['error'] != null) {
        // Carry the status code even though the message came from the
        // backend: callers need to tell "your session is gone" (401/403)
        // apart from any other refusal.
        throw ApiException(ApiErrorKind.server,
            statusCode: res.statusCode,
            serverMessage: data['error'].toString());
      }
      throw ApiException(ApiErrorKind.uploadFailed, statusCode: res.statusCode);
    }
    return data;
  }

  Future<dynamic> get(String path) => request(path);
  Future<dynamic> post(String path, [Object? body]) =>
      request(path, method: 'POST', body: body ?? {});
  Future<dynamic> put(String path, Object? body) =>
      request(path, method: 'PUT', body: body);
  Future<dynamic> patch(String path, Object? body) =>
      request(path, method: 'PATCH', body: body);
  Future<dynamic> delete(String path, [Object? body]) =>
      request(path, method: 'DELETE', body: body);
}
