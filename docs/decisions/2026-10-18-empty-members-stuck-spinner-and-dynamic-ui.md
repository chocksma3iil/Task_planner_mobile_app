# Empty-Members and Stuck-Spinner Fix plus Dynamic Task UI

- Date: 2026-10-18
- Status: approved (user approved fixes and features on 2026-10-18)
- Context: device testing reported the admin Members tab stuck on "No members yet" and the project-owner screen stuck on a spinner. Reproduction in widget tests traced both symptoms to one root cause plus a few state-handling bugs. The user also asked for richer task screens.
- Root cause: the shared button theme used `minimumSize: Size.fromHeight(48)`, which implies infinite minimum width; the Confirm button in the members card then forced an unbounded `Row`, throwing ~23 cascading "infinite width" exceptions that emptied the lists. Fixed to `Size(0, 48)` in `lib/core/theme.dart`.
- Secondary fixes: `visibleMembersProvider` no longer collapses account loading into an empty list; tabs use explicit `when` handling with retry (`ErrorState`) instead of `.value` fallbacks; `MemberService.watchVisibleMembers` throws a clear `StateError` for a non-admin without a project instead of crashing on `projectId!`.
- Decision: pending members are shown by name to everyone; the "Waiting for confirmation" section, status chips, and Confirm action remain owner/admin only (access-control rule). Non-admins on Tasks use their own `projectId` directly and never wait on the projects stream.
- Features added (same approval): stats cards (Due today / Overdue / Done, animated counts, tap to filter), swipe actions with undo snackbar (right completes or reopens, left deletes with recreate-undo), grouped sections in the All view (Overdue, Today, Upcoming, No due date, Completed), debounced search on members and tasks, and pull-to-refresh on all tabs.
- Verification: `flutter analyze` clean; `flutter test` 30/30 passed, including role-based reproduction tests in `test/home_screen_test.dart` that failed before the fix.
- Reverses: nothing; complements the 2026-10-11 architecture approval.
- Still open (resolved later the same day): dark-mode toggle and grouped sections in filtered views — both applied, see `2026-10-18-theme-mode-preference.md`. Swipe-delete undo recreates the task with a new id.
