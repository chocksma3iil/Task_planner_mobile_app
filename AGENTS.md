# Project Agent Instructions

## Project

Build a task planner mobile application using Flutter and Dart.

The first release uses a FastAPI + MySQL backend (approved 2026-10-21), so the app is online-only; local accounts are required.

Read `PROJECT_BRIEF.md` and relevant files in `docs/` before working.

## Responsibilities

- Understand the existing project before proposing changes.
- Reuse suitable existing code and dependencies.
- Keep implementations minimal, readable, maintainable, and testable.
- Follow the approved architecture and business rules.
- Explain technical decisions in simple language.
- Identify assumptions and unresolved requirements explicitly.

## Mandatory Development Workflow

For every meaningful change:

**Inspect → Propose → Stop → Approve → Implement → Verify → Stop**

Do not interpret a discussion or recommendation as approval.

## Approval Requirements

Ask for explicit approval before:

- Creating or changing the architecture.
- Adding or removing dependencies.
- Changing data models or persistence.
- Introducing services, APIs, AI integrations, or external systems.
- Changing application behavior or business rules.
- Modifying project structure in a way that affects architecture.

## Coding Rules

- Do not create unnecessary layers, abstractions, or files.
- Keep business rules separate from UI code and database implementation.
- Give each function a clear, single responsibility.
- Add a short docstring when a function's purpose or inputs and outputs are not obvious.
- Handle errors explicitly.
- Never claim that tests passed unless they were executed and verified.
- Update relevant documentation after approved changes.

## Phase

Discovery is complete; Milestones 1–4 are built (see `.kilo/plans/proposal-progress.md` and the approval decisions in docs/decisions/). The backend decision (2026-10-21) replaced local SQLite persistence with a FastAPI + MySQL API; feature routes live under `/api/v1` and `/health` stays unversioned. Local development uses Docker Compose for the API, MySQL, and phpMyAdmin; the Flutter SDK stays on the host (see README.md and `docs/decisions/2026-10-22-local-development-onboarding.md`).

A validation cycle on 2026-10-30 replayed the full plan on a rebuilt database: backend **88/88**, Flutter **100/100**, `flutter analyze` **0 errors / 0 warnings / 17 infos**, and E2E **E1-E16 all PASS** on the real stack (web-server Flutter app + Chrome CDP), including the new Planner scenario. On 2026-10-31 v1.1 started: A10 self-service password reset and A11 token-version revocation shipped (decision `docs/decisions/2026-10-30-password-reset-and-session-revocation.md`), D06 audit log shipped (decision `docs/decisions/2026-10-31-audit-log.md`, migration `0006_audit_logs`), E03 project exports shipped (decision `docs/decisions/2026-10-31-project-exports.md`), D05 comments/mentions shipped (decision `docs/decisions/2026-10-31-comments-mentions.md`, migration `0007_comments`), v2.0 AI layer shipped (decision `docs/decisions/2026-10-31-ai-layer.md`, migration `0008_ai_consent`), A12 2FA TOTP shipped (decision `docs/decisions/2026-10-31-2fa.md`, migration `0009_2fa`), B08 member leave/transfer shipped (decision `docs/decisions/2026-10-31-member-leave-transfer.md`), B05 member search and D02 SMTP tests closed, migrations applied through the container hook; totals are now backend **135/135**, Flutter **110/110**, E2E **E1-E22 PASS**. Phase 0 defects BD1-BD10 and the audit P0/P1 items are closed; the subtask no-op, dashboard default project, bulk selection, team-lead member confirmation and role refresh on app resume were fixed during the campaign. NF5 performance (3 projects / 50 members / 200 tasks), NF6 dependency scans and NF7 accessibility (4 tests; two real overflow bugs fixed in `MemberCard` and `TaskTile`) are measured. Widget coverage for archive/restore, dashboard, notifications, the viewer read-only shell and Planner was added against an extended fake API. Results, residual gaps and evidence are in `TEST_PLAN.md` §17; the stabilization decisions are in `docs/decisions/2026-10-27-phase-0-stabilization.md` and `docs/decisions/2026-10-28-team-lead-member-ui-and-role-refresh.md`. The Windows debug build from 2026-10-28 remains valid; the Android debug build could not run because this machine has no Android SDK. Docker is operational again: `docker compose up -d` and `docker compose exec -T api …` work, so suites and migrations now run directly (restart Docker Desktop if the CLI ever blocks again). Nothing is committed or pushed.

On 2026-11-15 the AI layer was made operational on this machine: `AI_MODEL` is `llama3.2:latest` (3B) because `qwen2.5:7b` exhausted the 4 GB GPU / 16 GB RAM; Gmail SMTP (App Password in the gitignored `.env`) now delivers reset emails; the login screen remembers the last email and delegates password saving to the OS via autofill. Live AI timings: weekly-plan 6.2 s, briefing 1.0 s, capture 1.1 s, decompose 3.0 s; `test_ai.py` 8/8, `test_email.py` 4/4, `auth_flow_test.dart` 11/11. C: has only ~0.5 GB free; the unused 7B/14B Ollama models can be deleted if more space is needed.

For every new change, the Mandatory Development Workflow still applies: propose and wait for explicit approval before implementing. v1.0 work continues from the certified Phase 0 baseline; v1.1 and v2.0 (AI) remain in scope per `.kilo/plans/proposal-progress.md`.

## 3. Development Skills

Skills live in `.agents/skills/` (auto-discovered by OpenCode; the Ollama runner must be configured to load the same files).

A skill is a reusable procedure that tells an agent how to perform a type of work. It is different from AGENTS.md, which provides the general rules.

- `interactive-development` — the workflow for every change: Inspect → Understand → Propose → Stop for approval → Implement minimally → Verify → Record and stop. Load the matching domain skill below for the work at hand.
- `database-design` — data model, schema, persistence, repositories, migrations; enforces the project/assignee/task rules.
- `access-control` — roles and capabilities (admin, project owner, user), membership approval, per-role workflows and tabs, project-scoped data visibility, enforcement in the application layer.
- `flutter-ui` — screens, widgets, navigation, theming, UI state; no business rules in UI, no direct database access.
- `testing-and-verification` — writing and running tests, reporting actual results only.
- `documentation-and-decisions` — keeping docs in sync, recording decisions under `docs/decisions/`.

Architectural changes require a new proposal and explicit approval, even when discovered during implementation.

## 4. Architecture Proposal

The canonical proposal and implementation history are consolidated in `.kilo/plans/proposal-progress.md`; individual approvals live in `docs/decisions/`.

This document describes the direction to evaluate, not a final approved design.

**Task Planner — Architecture Proposal**

1. **Business Direction** — Build a mobile task planner. The first release focuses on task management and daily planning. AI planning, cloud sync, and external collaboration are not assumed for the first release. The brief also adds projects as a grouping concept and task assignees (name + position, each assignee belongs to a project). Accounts use login/sign-up screens and three cumulative roles (admin, project owner, user); admins create projects and assign owners, owners confirm new members.
2. **Proposed Architecture Style** — A modular monolithic Flutter application in layers (models, screens, services, widgets, providers), plus one small FastAPI service. Avoid unnecessary backend infrastructure.
3. **Proposed Technology Candidates** — Flutter and Dart, Riverpod for state management and DI, FastAPI + MySQL for persistence, go_router for navigation, Flutter testing tools, pytest. The approved build follows this list; SQLite/Drift was replaced by the backend.
4. **Proposed Component Boundaries** — Presentation; Application and Business Logic; Domain; Data; Auth (local credentials, session, role checks); Notifications (email via device mail app, proposed); Integrations (e.g. local notifications). Future AI integration, if approved, must operate through controlled application operations and never bypass business rules or modify stored tasks without user authorization.
5. **Proposed Project Organization** — Flutter: `lib/app/`, `lib/core/`, `lib/models/`, `lib/providers/`, `lib/screens/`, `lib/services/`, `lib/widgets/`, `test/`. Backend: `backend/app/{api,core,models,schemas,services}`, `backend/tests/`, `backend/alembic/`. Create only the folders needed for approved features.
6. **Constraints** — Task data requires the API (online-only; offline sync is not in scope); bcrypt password hashes and role/assignment enforcement on the server; UI must not call the API or database directly; business rules testable without the UI; minimal dependencies and abstractions; no cloud auth provider without approval.
7. **Proposed Data Model (draft)** — Three tables: `projects` (with `owner_id`), `assignees` (with `project_id`, login email, password hash, role, pending/active status, approved_by), `tasks` (with `project_id` and optional `assignee_id`). Confirmed rules: a task is assigned either to its project as a whole or to one person from that project (never both); a person assignee must belong to the task's project; each person belongs to exactly one project (Option A). Only admins create projects, assign owners, and manage roles; self-registered users stay pending until the project owner confirms them.
8. **Open Decisions** — Final first-release features (including whether projects/assignees ship in v1); first-admin bootstrap; password recovery without a backend; task statuses, priorities, due-date behavior; categories vs projects; whether the assignee is optional; email notification scope and delivery; local notifications; export and restore; exact dependency choices, code organization, and where assignee management lives.
9. **Approval Status** — **APPROVED FOR IMPLEMENTATION (2026-10-11); AMENDED (2026-10-21)** to a FastAPI + MySQL backend and a layer-first Flutter layout. Milestones 1–4 built (`task_planner/` + `backend/`); see `.kilo/plans/proposal-progress.md`. New changes still follow Inspect → Propose → Approve → Implement → Verify.

## 5. How to Give This to OpenCode and Ollama

The project files are shared, but the agent configuration is separate.

**OpenCode**

Put AGENTS.md in the repository root. OpenCode auto-discovers `.agents/skills/` — no extra skill configuration needed. Ask OpenCode to read the shared brief and proposal before doing anything.

**Ollama-powered agent**

Configure the agent runner to supply the same documents and workflow rules in its context. Ollama itself runs the model; your surrounding agent software determines how files, skills, and tools are loaded.

Recommendation: use OpenCode as the primary implementation agent and the Ollama-powered agent as a reviewer or planning assistant initially. That avoids conflicting edits and lets you compare their reasoning.

## 6. The First Prompt to Send

Once these documents are available, send this to OpenCode first. Use the same prompt with the Ollama agent when you want a second opinion.

> Read AGENTS.md, PROJECT_BRIEF.md, and `.kilo/plans/proposal-progress.md`.
>
> We are in the discovery phase of a Flutter task planner project.
>
> Inspect the repository and evaluate the proposed business direction and architecture.
>
> Identify:
> 1. Missing business requirements.
> 2. Unanswered questions affecting the first release.
> 3. Architectural risks or unnecessary complexity.
> 4. Whether the proposed technology choices are appropriate.
> 5. The smallest useful next step.
>
> Do not implement code, create files, install dependencies, or modify the repository.
>
> Present a concise report with recommendations, assumptions, and trade-offs. Distinguish recommendations from decisions requiring my approval.
>
> Stop and wait for my feedback.

Our immediate goal is to validate the product idea and architecture, not to build the app yet. Once the discovery reports are reviewed, we can finalize the business requirements and approve the technical architecture before starting implementation.