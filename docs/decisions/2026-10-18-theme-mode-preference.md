# Theme Mode Preference (System / Light / Dark)

- Date: 2026-10-18
- Status: approved (user selected the dark-mode toggle and grouped sections everywhere on 2026-10-18)
- Context: the theme already supported dark colors (`buildTheme(Brightness.dark)`), but the app was hard-coded to `ThemeMode.system` with no way to override it. The user also asked for task group headers in filtered views, not only in All.
- Options considered:
  1. `shared_preferences` package — idiomatic but adds a new dependency; the project rule is minimal dependencies.
  2. New `AppSettings` key/value table in the existing drift database — no new dependency, reuses local storage, one small migration.
  3. In-memory only — loses the choice on restart; poor UX.
- Decision: option 2. Schema bumped 1 → 2 with `onUpgrade` creating `AppSettings` (key TEXT PRIMARY KEY, value TEXT); existing device databases migrate automatically on next launch. `ThemeModeController` (Riverpod `Notifier` in `lib/features/settings/application/theme_mode_provider.dart`) defaults to system, loads the saved value, and persists changes; a failed read/write keeps the in-memory choice. The AppBar theme picker (System / Light / Dark) sits before the account menu and is available to every role.
- Also decided: task list sections (Overdue, Today, Upcoming, No due date, Completed) now appear in every filter view; empty sections stay hidden.
- Verification: `flutter analyze` clean; `flutter test` 32/32 passed, including a settings round-trip test and a widget test that switches to Dark and reads the stored value back.
- Reverses: the "still open" dark-mode and grouped-sections items in `2026-10-18-empty-members-stuck-spinner-and-dynamic-ui.md`.
- Still open: whether the theme picker should also appear on the login screen.
