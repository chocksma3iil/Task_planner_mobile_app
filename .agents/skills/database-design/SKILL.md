---
name: database-design
description: Use when changing the data model, database schema, persistence code, repositories, or migrations (SQLite with Drift). Enforces the project, assignee, and task rules from the brief and proposal. Schema and persistence changes need explicit user approval before implementation.
---

# Database Design

Source of truth for the model: PROJECT_BRIEF.md (Task Assignment, Assignee Management) and docs/ARCHITECTURE_PROPOSAL.md §8 (draft data model — proposed, not approved).

## Current model (draft)

- `projects`: id, name, optional description, status (active/archived), `owner_id` (assigned by an admin), created_at.
- `assignees`: id, name, position (job title, display only — not the access role), `project_id` (each person belongs to exactly one project; admins act across all projects), email (unique login), password_hash (salted), role (admin/project_owner/user, cumulative), status (pending/active), `approved_by` (confirming owner's id, null until confirmed), created_at.
- `tasks`: id, title (required), optional description, status (to do/completed), priority (low/medium/high), optional due_date, `project_id` (required), `assignee_id` (optional), created_at, updated_at, completed_at.

## Assignment rules

- A task belongs to a project and has at most one assignee: the project as a whole (`assignee_id` NULL — several people affected) or exactly one person (`assignee_id` set). Never both.
- A person assignee must belong to the task's project. Enforce this in the application/business-logic layer, not just the UI.
- Assigning a task to a project other than its own is out of scope unless approved.

## Access rules

See the `access-control` skill for roles, capabilities, membership approval, and enforcement. This skill owns the tables and columns; `access-control` owns who may do what.

## Constraints

- Offline-first: task management must work with no network.
- UI code must never access the database directly; business rules must be testable without the UI.
- Changing the model, tables, or persistence approach requires a proposal and explicit approval (see `interactive-development`, AGENTS.md approval requirements).
