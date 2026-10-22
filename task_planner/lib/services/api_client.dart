import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP access to the FastAPI backend.
///
/// Errors are normalized to the shapes the screens already handle:
///  * [StateError] for HTTP error details, server validation failures,
///    unreachable-server problems, and timeouts;
///  * [ArgumentError] when the server reports a `project_required` or
///    `invalid_assignment` code (assignment / project-choice violations).
abstract class ApiClient {
  String get baseUrl;

  /// Bearer token attached to every request after a successful login.
  void setToken(String token);

  void clearToken();

  Future<dynamic> get(String path);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]);

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]);

  Future<dynamic> delete(String path);
}

/// [ApiClient] built on `package:http`. Tests inject a fake client instead.
class HttpApiClient implements ApiClient {
  HttpApiClient(
    this.baseUrl, {
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  static const _offlineMessage =
      'Could not reach the server. Check that the API is running.';

  @override
  final String baseUrl;

  /// Per-request timeout; longer than that is reported as offline.
  final Duration timeout;
  final http.Client _http;
  String? _token;

  /// Current bearer token (null when logged out). Exposed for tests/state UI.
  String? get token => _token;

  @override
  void setToken(String token) => _token = token;

  @override
  void clearToken() => _token = null;

  @override
  Future<dynamic> get(String path) => _request('GET', path);

  @override
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _request('POST', path, body: body);

  @override
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _request('PATCH', path, body: body);

  @override
  Future<dynamic> delete(String path) => _request('DELETE', path);

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    final encoded = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      final request = switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'POST' => _http.post(uri, headers: headers, body: encoded),
        'PATCH' => _http.patch(uri, headers: headers, body: encoded),
        'DELETE' => _http.delete(uri, headers: headers),
        _ => throw UnsupportedError('HTTP $method is not supported.'),
      };
      response = await request.timeout(timeout);
    } on UnsupportedError {
      rethrow;
    } on TimeoutException {
      throw StateError(_offlineMessage);
    } catch (_) {
      throw StateError(_offlineMessage);
    }
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        throw StateError('The server sent an unreadable response.');
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final detail = decoded is Map ? decoded['detail'] : null;
    String message;
    String? code;
    if (detail is Map) {
      message = detail['message']?.toString() ?? 'Request failed.';
      code = detail['code']?.toString();
    } else {
      message =
          detail?.toString() ?? 'Request failed (HTTP ${response.statusCode}).';
    }
    if (code == 'invalid_assignment' || code == 'project_required') {
      throw ArgumentError(message);
    }
    throw StateError(message);
  }
}
