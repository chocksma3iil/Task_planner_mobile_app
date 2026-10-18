---
name: testing-and-verification
description: Use when writing or running tests, or when asked to verify changes. Runs the relevant Flutter tests, inspects the results, and reports actual outcomes. Never claims tests passed without executing them.
---

# Testing and Verification

## Rules

- Test business rules independently of the UI; widget tests cover screens and flows.
- Run the narrowest relevant scope first (single test or file), then broaden only if needed.
- Inspect failures and the actual diff; report real results, including unresolved failures.
- Never invent test results. "Not run" is an acceptable, honest report.
- Keep changes small and test them independently (see `interactive-development`).

## Scope notes

- No test infrastructure or app code exists yet; do not scaffold a test suite until the architecture and dependencies are approved.
- Assignment and project rules (see `database-design`) are the first candidates for unit tests once implementation is approved, since they must hold without the UI. Role and membership checks (pending users blocked, owner-only confirmation, admin-only role changes) belong in that same testable layer.
