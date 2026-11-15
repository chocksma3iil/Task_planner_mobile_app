import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'providers/api_providers.dart';
import 'services/api_client.dart';

/// Base URL of the FastAPI backend (all feature routes live under `/api/v1`).
///
/// Override per platform/build, e.g. for an Android emulator:
/// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1`
const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000/api/v1',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = HttpApiClient(_apiBaseUrl);

  // The saved token is restored and validated by TaskPlannerApp before the
  // router leaves the splash screen.
  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
      ],
      child: const TaskPlannerApp(),
    ),
  );
}
