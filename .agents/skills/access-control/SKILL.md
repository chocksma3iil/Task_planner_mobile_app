---
name: access-control
description: Use when checking who may do what. Covers the three roles (admin, project owner, user), each role's responsibilities, per-role workflows, which tabs each role sees, project-scoped data visibility, join approval, and where access checks must be enforced.
---

# Access Control

Source of truth: PROJECT_BRIEF.md (§5 rules, Accounts and Roles) and docs/ARCHITECTURE_PROPOSAL.md §8. Decision recorded in `docs/decisions/2026-10-11-local-auth-and-roles.md`.

## Roles

Three cumulative roles: an admin can do everything a project owner and a user can do; a project owner everything a user can do.

- **Admin** — owns the system: creates projects, assigns project owners, creates users anywhere, manages roles, confirms any join request, and sees every tab and all data.
- **Project owner** — owns their projects: confirms or rejects join requests, sees all members and their statuses (pending/active), manages tasks and assignments, creates users inside their own projects. No project creation, no role changes.
- **User** — works their tasks: views and completes assigned tasks, manages tasks in their own project. Must sign up and be confirmed before first login.

## Capability matrix

| Capability | User | Project Owner | Admin |
|---|---|---|---|
| Log in (active accounts only) | ✓ | ✓ | ✓ |
| View and complete assigned tasks | own project | own projects | all projects |
| Create, edit, delete tasks | own project | own projects | all projects |
| Assign tasks to the project or a person | — | own projects | all projects |
| Confirm or reject join requests | — | own projects | all projects |
| Create users (role user) | — | own projects | anywhere |
| Create projects, assign owners, manage roles | — | — | ✓ |

## Workflows

**New user (self-registration).** Open app → sign-up page (name, email, password, choose project) → account created as pending → relevant project owner confirms → user logs in → sees today's tasks. Pending users cannot log in.

**Project owner (enrollment).** Log in → Members tab → pending-requests section lists everyone waiting for their projects → confirm or reject → member becomes active and can log in. Roster shows every member with pending/active status.

**Admin (setup).** Log in → Projects tab → create project → assign its owner → optionally create users directly (active immediately). Can open every tab across all projects.

## Tabs per role (approved 2026-10-18)

- **Projects** — admin only: create projects, list all, assign owners.
- **Members** — all roles, scoped: user sees their own project's roster; owner sees their projects' rosters with pending/active statuses plus the pending-requests section; admin sees everyone including roles.
- **Tasks** — all roles, scoped: user sees own project's tasks; owner their projects'; admin all.
- **Mine** — owner and user (not admin, who can never be an assignee): tasks assigned to the logged-in person only (`assignee_id` = viewer), enforced by `TaskService.watchTasksAssignedTo`.
- **Approvals** live inside the Members tab as the pending-requests section (owner/admin only), not as a separate tab — the brief asks for minimal screens.

Tab changes are business-rule changes; record them under `docs/decisions/`.

## Data scoping

Everyone sees only their own projects' data — tasks, members, and requests are always filtered to the viewer's project(s). Only admins bypass the filter. Scoping is enforced in the application layer, not just by hiding tabs.

## Membership lifecycle

- Admins and project owners create active users directly.
- Self-registered users start as pending and cannot log in until the relevant project owner (or an admin) confirms them; confirmation records the owner's id in `approved_by`.
- Credentials live only in the local person table; passwords are salted hashes, never plain text.
- Key events raise an email notification through the device's mail app (proposed): a new sign-up notifies the project owner, approval or rejection notifies the user, a new assignment notifies the assignee.

## Enforcement

- Role, scope, and membership checks belong in the application/business-logic layer. The UI may hide actions, but must never be the only check.
- Changing roles, the matrix, workflows, tabs, or the approval flow is a business-rule change: propose and wait for approval (see `interactive-development`).
