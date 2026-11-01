import '../core/rules.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'data_sync.dart';

/// User management against the API: creation by admins/owners, owner
/// confirmation of self-registered accounts, and admin-only role changes.
///
/// The server enforces who may do what; the caller is derived from the
/// session token.
class MemberService {
  MemberService(this._client);

  final ApiClient _client;

  /// Creates an active user directly. Admins may create anywhere with any
  /// role; owners may only create plain users inside their own project.
  Future<Account> createUser({
    required String name,
    required String email,
    required String password,
    String? position,
    int? projectId,
    String role = Roles.user,
  }) async {
    final json = await _client.post('/members', {
      'name': name,
      'email': email,
      'password': password,
      'position': ?position,
      'project_id': ?projectId,
      'role': role,
    });
    DataSync.instance.ping();
    return Account.fromJson(json as Map<String, dynamic>);
  }

  /// Moves a pending account to active. Allowed for admins everywhere and
  /// for owners inside their own project. Records the confirmer.
  Future<Account> confirmUser({required int userId}) async {
    final json = await _client.post('/members/$userId/confirm');
    DataSync.instance.ping();
    return Account.fromJson(json as Map<String, dynamic>);
  }

  /// Admin-only role changes.
  Future<Account> changeRole({
    required int userId,
    required String role,
  }) async {
    final json = await _client.post('/members/$userId/role', {'role': role});
    DataSync.instance.ping();
    return Account.fromJson(json as Map<String, dynamic>);
  }

  /// One page of members visible to the caller: everyone for admins, own
  /// project otherwise. A non-admin without a project gets a clear server
  /// error.
  Future<AccountList> fetchVisibleMembers({
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _client.get(
      '/members?limit=$limit&offset=$offset',
    ) as Map<String, dynamic>;
    return AccountList.fromJson(json);
  }

  /// Members visible to the caller, refreshed after every mutation.
  Stream<AccountList> watchVisibleMembers({int page = 1, int pageSize = 20}) {
    final offset = (page - 1) * pageSize;
    return watchFromApi(
      () => fetchVisibleMembers(limit: pageSize, offset: offset),
    );
  }
}
