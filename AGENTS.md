# Project Agent Instructions

## Project

Build a task planner mobile application using Flutter and Dart.

The first release is intended to be offline-first, with local accounts required.

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

Discovery is complete and Milestone 1 is built (see IMPLEMENTATION_PLAN.md and the approval decision in docs/decisions/).

For every new change, the Mandatory Development Workflow still applies: propose and wait for explicit approval before implementing.

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

Create `docs/ARCHITECTURE_PROPOSAL.md` (done — canonical copy lives there).

This document describes the direction to evaluate, not a final approved design.

**Task Planner — Architecture Proposal**

1. **Business Direction** — Build a mobile task planner that works offline. The first release focuses on task management and daily planning. AI planning, cloud sync, and external collaboration are not assumed for the first release. The brief also adds projects as a grouping concept and task assignees (name + position, each assignee belongs to a project). Accounts are local-only with login/sign-up screens and three cumulative roles (admin, project owner, user); admins create projects and assign owners, owners confirm new members.
2. **Proposed Architecture Style** — A modular monolithic Flutter application organized by feature and responsibility. Avoid unnecessary backend infrastructure.
3. **Proposed Technology Candidates** — Flutter and Dart, Riverpod for state management and DI, SQLite with Drift for persistence, go_router for navigation, Flutter testing tools. These are proposals requiring review, not approved dependencies.
4. **Proposed Component Boundaries** — Presentation; Application and Business Logic; Domain; Data; Auth (local credentials, session, role checks); Notifications (email via device mail app, proposed); Integrations (e.g. local notifications). Future AI integration, if approved, must operate through controlled application operations and never bypass business rules or modify stored tasks without user authorization.
5. **Proposed Project Organization** — `lib/app/`, `lib/core/`, `lib/features/tasks/`, `lib/features/planner/`, `lib/features/settings/`, `lib/features/auth/`, `lib/integrations/`, `test/`, `docs/`. Create only the folders needed for approved features.
6. **Constraints** — No network dependency for task management; local-only accounts with salted password hashes; UI must not access the database directly; business rules testable without the UI; minimal dependencies and abstractions; no backend or cloud auth without approval.
7. **Proposed Data Model (draft)** — Three tables: `projects` (with `owner_id`), `assignees` (with `project_id`, login email, password hash, role, pending/active status, approved_by), `tasks` (with `project_id` and optional `assignee_id`). Confirmed rules: a task is assigned either to its project as a whole or to one person from that project (never both); a person assignee must belong to the task's project; each person belongs to exactly one project (Option A). Only admins create projects, assign owners, and manage roles; self-registered users stay pending until the project owner confirms them.
8. **Open Decisions** — Final first-release features (including whether projects/assignees ship in v1); first-admin bootstrap; password recovery without a backend; task statuses, priorities, due-date behavior; categories vs projects; whether the assignee is optional; email notification scope and delivery; local notifications; export and restore; exact dependency choices, code organization, and where assignee management lives.
9. **Approval Status** — **APPROVED FOR IMPLEMENTATION (2026-10-11).** Milestone 1 built in `task_planner/`; see IMPLEMENTATION_PLAN.md. New changes still follow Inspect → Propose → Approve → Implement → Verify.

## 5. How to Give This to OpenCode and Ollama

The project files are shared, but the agent configuration is separate.

**OpenCode**

Put AGENTS.md in the repository root. OpenCode auto-discovers `.agents/skills/` — no extra skill configuration needed. Ask OpenCode to read the shared brief and proposal before doing anything.

**Ollama-powered agent**

Configure the agent runner to supply the same documents and workflow rules in its context. Ollama itself runs the model; your surrounding agent software determines how files, skills, and tools are loaded.

Recommendation: use OpenCode as the primary implementation agent and the Ollama-powered agent as a reviewer or planning assistant initially. That avoids conflicting edits and lets you compare their reasoning.

## 6. The First Prompt to Send

Once these documents are available, send this to OpenCode first. Use the same prompt with the Ollama agent when you want a second opinion.

> Read AGENTS.md, PROJECT_BRIEF.md, and docs/ARCHITECTURE_PROPOSAL.md.
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