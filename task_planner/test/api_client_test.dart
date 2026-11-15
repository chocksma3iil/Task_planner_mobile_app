import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_planner/services/api_client.dart';
import 'package:task_planner/services/auth_service.dart';

/// Unit tests for the HTTP layer: status/detail mapping (StateError vs
/// ArgumentError), token handling, and offline behavior.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MockClient clientReturning(int status, Object? body) {
    return MockClient((request) async {
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  group('HttpApiClient error mapping', () {
    test('2xx responses return the decoded body', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(200, {'id': 7}),
      );
      expect(await client.get('/x'), {'id': 7});
    });

    test('empty 2xx responses (204) return null', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(204, null),
      );
      expect(await client.delete('/x'), isNull);
    });

    test('string detail becomes StateError', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(401, {
          'detail': 'Wrong email or password.',
        }),
      );
      expect(
        () => client.post('/auth/login', {'email': 'a', 'password': 'b'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Wrong email or password.',
          ),
        ),
      );
    });

    test('coded invalid_assignment becomes ArgumentError', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(400, {
          'detail': {
            'code': 'invalid_assignment',
            'message': 'Assignee must belong to the task project.',
          },
        }),
      );
      expect(
        () => client.post('/tasks', {'project_id': 1}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Assignee must belong to the task project.',
          ),
        ),
      );
    });

    test('coded project_required becomes ArgumentError', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(400, {
          'detail': {
            'code': 'project_required',
            'message': 'Choose a project to join.',
          },
        }),
      );
      expect(
        () => client.post('/auth/signup', {'name': 'X'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Choose a project to join.',
          ),
        ),
      );
    });

    test('transport failure becomes a clear StateError', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: MockClient((_) async {
          throw http.ClientException('connection refused');
        }),
      );
      expect(
        () => client.get('/projects'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Could not reach the server. Check that the API is running.',
          ),
        ),
      );
    });

    test('timeout becomes the offline StateError', () async {
      final client = HttpApiClient(
        'http://api.test',
        timeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{}', 200);
        }),
      );
      expect(
        () => client.get('/projects'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Could not reach the server. Check that the API is running.',
          ),
        ),
      );
    });

    test('unreadable JSON becomes a clear StateError', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(
        () => client.get('/projects'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'The server sent an unreadable response.',
          ),
        ),
      );
    });

    test('an HTTP error without detail keeps the status code', () async {
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(500, null),
      );
      expect(
        () => client.get('/projects'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Request failed (HTTP 500).',
          ),
        ),
      );
    });

    test('sends the bearer token after setToken', () async {
      late String? seenAuth;
      final client = HttpApiClient(
        'http://api.test',
        httpClient: MockClient((request) async {
          seenAuth = request.headers['Authorization'];
          return http.Response('{}', 200);
        }),
      );
      client.setToken('abc123');
      await client.get('/auth/me');
      expect(seenAuth, 'Bearer abc123');
      client.clearToken();
      await client.get('/auth/me');
      expect(seenAuth, isNull);
    });

    test('401 on an authenticated request notifies the handler', () async {
      var calls = 0;
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(401, {
          'detail': 'Invalid or expired token.',
        }),
      );
      client.setUnauthorizedHandler(() => calls++);
      client.setToken('expired-token');
      await expectLater(
        client.get('/members'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Invalid or expired token.',
          ),
        ),
      );
      expect(calls, 1);
    });

    test('401 without a token leaves the handler untouched', () async {
      var calls = 0;
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(401, {
          'detail': 'Wrong email or password.',
        }),
      );
      client.setUnauthorizedHandler(() => calls++);
      await expectLater(
        client.post('/auth/login', {'email': 'a', 'password': 'b'}),
        throwsA(isA<StateError>()),
      );
      expect(calls, 0);
    });
  });

  group('AuthService over HTTP', () {
    test('login stores the token and returns the account', () async {
      SharedPreferences.setMockInitialValues({});
      final client = HttpApiClient(
        'http://api.test',
        httpClient: clientReturning(200, {
          'access_token': 'tok-1',
          'token_type': 'bearer',
          'account': {
            'id': 3,
            'name': 'Bob',
            'position': null,
            'project_id': 1,
            'email': 'bob@example.com',
            'role': 'user',
            'status': 'active',
            'approved_by': 1,
            'created_at': '2026-10-21T10:00:00',
          },
        }),
      );
      final auth = AuthService(client);
      final account = await auth.login(
        email: 'bob@example.com',
        password: 'pw',
      );
      expect(account.id, 3);
      expect(account.role, 'user');
      expect(client.token, 'tok-1');
    });
  });
}
