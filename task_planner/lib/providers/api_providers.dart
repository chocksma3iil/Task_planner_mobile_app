import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';

/// The API client. Overridden in `main` with the HTTP implementation.
final apiClientProvider = Provider<ApiClient>(
  (_) => throw UnimplementedError('API client not initialized.'),
);
