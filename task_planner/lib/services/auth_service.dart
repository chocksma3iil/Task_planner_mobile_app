import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Login, sign-up, and session-adjacent account operations.
///
/// The server enforces the business rules (bootstrap admin, unique email,
/// pending accounts); this class only transports the requests and stores
/// the returned session token.
class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  /// Key used to persist the JWT token in shared preferences.
  static const _sessionTokenKey = 'session_token';

  /// Registers an account. The very first account becomes the active admin;
  /// later sign-ups must pick a project and start pending. A missing project
  /// surfaces as [ArgumentError] (server code `project_required`).
  Future<Account> signUp({
    required String name,
    required String email,
    required String password,
    String? position,
    int? projectId,
  }) async {
    final json = await _client.post('/auth/signup', {
      'name': name,
      'email': email,
      'password': password,
      'position': ?position,
      'project_id': ?projectId,
    });
    return Account.fromJson(json as Map<String, dynamic>);
  }

  /// Returns the account when credentials are valid and active.
  ///
  /// Throws [StateError] for unknown accounts, wrong passwords, and pending
  /// accounts awaiting owner confirmation. On success the session token is
  /// stored on the client and persisted to shared preferences.
  Future<Account> login({
    required String email,
    required String password,
  }) async {
    final json = await _client.post('/auth/login', {
      'email': email,
      'password': password,
    });
    final token = json['access_token'] as String;
    _client.setToken(token);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_sessionTokenKey, token);
    });
    return Account.fromJson(json['account'] as Map<String, dynamic>);
  }

  /// Requests a single-use password-reset code by email and returns the
  /// server's confirmation message.
  ///
  /// The server answers the same way whether or not the account exists, so
  /// the message must not be treated as proof that the account is real.
  Future<String> requestPasswordReset(String email) async {
    final json = await _client.post('/auth/forgot-password', {
      'email': email.trim(),
    });
    return _messageFrom(json, 'If the account exists, a reset code was sent.');
  }

  /// Sets a new password from an emailed code and returns the server's
  /// confirmation message.
  ///
  /// Throws [StateError] when the code is unknown, already used, or expired.
  /// On success the server also revokes every token issued before the reset.
  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final json = await _client.post('/auth/reset-password', {
      'email': email.trim(),
      'code': code.trim(),
      'new_password': newPassword,
    });
    return _messageFrom(json, 'Password updated. Log in with the new password.');
  }

  String _messageFrom(dynamic json, String fallback) {
    if (json is Map && json['message'] != null) {
      return json['message'].toString();
    }
    return fallback;
  }
}
