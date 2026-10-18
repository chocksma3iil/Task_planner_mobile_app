---
name: interactive-development
description: Use for any change to this repo. Follow the Inspect, Understand, Propose, Stop for approval, Implement minimally, Verify, Record workflow, and load the matching domain skill for the work at hand.
---

# Interactive Development

The workflow for every meaningful change. AGENTS.md holds the binding rules; this skill holds the procedure.

**Step 1 — Inspect.** Read AGENTS.md, PROJECT_BRIEF.md, and relevant docs. Inspect existing files, find reusable code and tests. Do not assume the repository is empty.

**Step 2 — Understand.** Identify the intended user outcome, the relevant business rules, missing information, and conflicting requirements. State assumptions explicitly.

**Step 3 — Propose.** Before changing files, describe the problem, the solution, the files that would change, new dependencies or architectural impact, and how it will be tested.

**Step 4 — Stop and wait.** Request explicit approval. Do not implement until approval is received. Architectural changes need a new proposal even when discovered mid-implementation.

**Step 5 — Implement minimally.** Make only the approved changes. Reuse existing utilities and patterns. No unrelated refactoring, no silent scope expansion.

**Step 6 — Verify.** Run relevant tests and checks, inspect the changes, report actual results and unresolved failures. Never invent test results.

**Step 7 — Record and stop.** Update relevant documentation, report what changed and what remains, then stop and wait.

## Which domain skill to load

- Data model, schema, persistence, repositories, migrations → `database-design`
- Roles, permissions, join approval, who-can-do-what → `access-control`
- Screens, widgets, navigation, theming, UI state → `flutter-ui`
- Writing or running tests, verifying changes → `testing-and-verification`
- Updating docs or recording a decision → `documentation-and-decisions`
