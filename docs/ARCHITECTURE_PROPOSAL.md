# Task Planner — Architecture Proposal

This document describes the direction to evaluate, not a final approved design.

## 1. Business Direction

Build a mobile task planner that works offline with local accounts.

The first release should focus on task management and daily planning.

AI planning, cloud synchronization, and external collaboration are not assumed to be part of the first release.

The brief also adds two requirements to evaluate for the first release: projects as a grouping concept, and task assignees (a person with a name and a position, where each assignee belongs to a project).

The first release also requires local accounts with login and sign-up screens and three cumulative roles (admin, project owner, user). Admins create projects and assign their owners; accounts live in the local person table — no backend.

## 2. Proposed Architecture Style

A modular monolithic Flutter application organized by feature and responsibility.

Avoid microservices and unnecessary backend infrastructure.

## 3. Proposed Technology Candidates

- Flutter and Dart for the mobile application.
- Riverpod for state management and dependency injection.
- SQLite with Drift for local persistence.
- go_router for navigation.
- Flutter testing tools for unit, widget, and integration tests.

These are proposals requiring review, not approved dependencies.

## 4. Proposed Component Boundaries

**Presentation**
Displays screens, forms, navigation, and UI state.

**Application and Business Logic**
Coordinates task operations and applies business rules.

**Domain**
Defines task concepts and rules independently of UI and database details.

**Data**
Implements repositories, database access, and persistence.

**Integrations**
Contains optional platform integrations, such as local notifications.

**Auth**
Verifies login credentials against the local person table, holds the session, and enforces role checks (admin, project owner, user). Local only — no network calls. Logging out clears the session.

**Notifications**
Sends email notifications for key events (proposed: new sign-up, approval or rejection, task assignment) through the device's email app. Proposed, not approved; needs connectivity when sending.

**Future AI Integration**
If approved later, AI may propose task plans through controlled application operations. It must not bypass business rules or modify stored tasks without appropriate user authorization.

## 5. Proposed Project Organization

- `lib/app/` — application entry and navigation.
- `lib/core/` — genuinely shared utilities and theme.
- `lib/features/tasks/` — task management.
- `lib/features/auth/` — login, sign-up, session, and role checks.
- `lib/features/planner/` — daily planning and task views.
- `lib/features/settings/` — application preferences.
- `lib/integrations/` — platform integrations added when needed.
- `test/` — automated tests.
- `docs/` — requirements, architecture, decisions, and development plans.

Create only the folders needed for approved features.

## 6. Constraints

- Task management must not depend on network availability.
- UI code must not access the database directly.
- Business rules must be testable independently of the UI.
- Keep dependencies and abstractions to a minimum.
- Accounts and credentials live only in the local database; passwords are stored as salted hashes, never plain text. No backend, sync, or cloud auth without approval.
- Email notifications go through the device's email app and need connectivity when sending; automatic sending without user action would need a backend (deferred).

## 7. Open Decisions

- Final first-release features. Required by the brief: tasks, projects, assignees, assignment, local accounts. Still open: notification scope, backup/restore, daily vs weekly views.
- Task statuses, priorities, and due-date behavior.
- Categories versus projects — projects are now proposed as a concrete entity, but the choice is not settled.
- Whether the assignee is optional or required on a task (the brief leaves this to the user).
- How the very first admin account is created on a fresh install.
- Password recovery or reset without a backend.
- Automatic email sending without user action (needs a backend; deferred).
- Exact tab structure per role (proposed in the access-control skill).
- Assigning a task to a project other than the task's own project is not supported in this draft; revisit only if cross-team assignment is needed.
- What happens to tasks assigned to a removed member.
- Local notifications.
- Export and restore.
- Exact dependency choices and code organization, including where project/assignee management lives in the feature structure.

## 8. Proposed Data Model (Draft — Not Approved)

Three tables, reflecting the brief's assignment requirements. A task has at most one assignee: either its project as a whole or one person from that project — never both.

**1. projects**

| Column | Purpose |
|---|---|
| id | Primary key |
| name | Project name |
| description | Optional description |
| status | Active or archived |
| owner_id | Project owner, assigned by an admin |
| created_at | Creation timestamp |

**2. assignees**

| Column | Purpose |
|---|---|
| id | Primary key |
| name | Person's name |
| position | Job title, e.g. Developer (display only; unrelated to the access `role`) |
| project_id | Project this person belongs to (admins act across all projects regardless) |
| email | Unique login identifier |
| password_hash | Salted password hash |
| role | admin, project_owner, or user (cumulative; unrelated to `position`) |
| status | pending (self-registered, awaiting owner confirmation) or active |
| approved_by | Owner who confirmed the account (null until confirmed) |
| created_at | Creation timestamp |

**3. tasks**

| Column | Purpose |
|---|---|
| id | Primary key |
| title | Required task title |
| description | Optional details |
| status | To do or completed |
| priority | Low, medium, or high |
| due_date | Optional deadline |
| project_id | Project the task belongs to (whole-project assignment when no person is set) |
| assignee_id | Optional assigned person; when set, must belong to the task's project |
| created_at | Creation timestamp |
| updated_at | Last modification timestamp |
| completed_at | Completion timestamp |

**Relationships**

```
Project: Mobile App
├── Assignees: Ahmed · Developer, Sara · Tester
└── Tasks: Fix login, Test release
```

**Confirmed rules**

- A task has at most one assignee target: the project or a person, never both (person assigned ⇔ `assignee_id` is set).
- A person assignee must belong to the same project as the task (`assignees.project_id` equals `tasks.project_id`). Enforce this at the application/business-logic layer.
- Each person belongs to exactly one project (Option A).

**Access rules**

- Only an admin creates projects and assigns project owners; only an admin creates owner/admin accounts or changes roles.
- Admins and project owners create active users directly. Self-registered users start as pending and cannot log in until the relevant project owner (or an admin) confirms them; confirmation records the owner's id in `approved_by`.
- Admins act across all projects; project owners and users act within their own project.

## 9. Approval Status

**APPROVED FOR IMPLEMENTATION (2026-10-11).** Milestone 1 built in `task_planner/` per `IMPLEMENTATION_PLAN.md`.

New changes still follow Inspect → Propose → Approve → Implement → Verify.
