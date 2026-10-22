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
  /// stored on the client.
  Future<Account> login({
    required String email,
    required String password,
  }) async {
    final json = await _client.post('/auth/login', {
      'email': email,
      'password': password,
    });
    _client.setToken(json['access_token'] as String);
    return Account.fromJson(json['account'] as Map<String, dynamic>);
  }
}
