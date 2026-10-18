import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database.dart';
import '../../auth/presentation/session_providers.dart';

/// Reads and writes device-level settings rows in the local database.
class SettingsService {
  SettingsService(this._db);

  final AppDatabase _db;

  Future<String?> read(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }
}

/// The app-wide theme mode, persisted in the local settings table.
///
/// Defaults to [ThemeMode.system] until the saved choice loads; a failed
/// read or write keeps the in-memory preference for the session.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'themeMode';

  @override
  ThemeMode build() {
    Future.microtask(_load);
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final raw = await SettingsService(ref.read(databaseProvider)).read(_key);
      final mode = switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
      if (mode != null) {
        state = mode;
      }
    } catch (_) {
      // Keep the system default; theme preference is non-critical.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await SettingsService(ref.read(databaseProvider))
          .write(_key, mode.name);
    } catch (_) {
      // Preference stays in memory for this session.
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
