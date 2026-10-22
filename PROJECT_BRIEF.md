# Project Brief — Task Planner

> **Amended 2026-10-21:** the approved build uses a FastAPI + MySQL backend and
> is online-only; the offline-first constraints below are superseded. See
> `docs/decisions/2026-10-21-fastapi-mysql-backend.md`. Task editing remains a
> required MVP feature.

## 1. Project Goal

Build a task planner mobile application that helps the user organize tasks and decide what to work on next.

The app should be simple, reliable, easy to use, and usable without an internet connection.

## 2. Target Platform

- Mobile application built with Flutter and Dart.
- Android is the initial target.
- Keep the architecture open to supporting iOS later.

## 3. First Release (MVP)

The first release should focus on essential task management:

- Create a task.
- Edit a task.
- Delete a task.
- Mark a task as completed.
- Reopen a completed task.
- Assign a priority.
- Optionally set a due date.
- View today's tasks.
- View upcoming and overdue tasks.
- Save tasks locally so they remain available after closing and reopening the app.
- Log in with an account (login page).
- Create an account (sign-up page).

## 4. Initial User Experience

The user should be able to open the app and quickly understand:

- What needs to be done today.
- Which tasks are overdue.
- Which tasks are most important.
- What has already been completed.

Avoid unnecessary screens and complicated workflows.

The app opens on a login page; new users reach the sign-up page from there.

## 5. Business Rules

- A task must have a title.
- A task is not required to have a due date.
- New tasks are incomplete by default.
- Completing a task records when it was completed.
- Reopening a task clears its completion timestamp.
- An incomplete task is overdue when its due date has passed.
- Completed tasks are not considered overdue.
- Task data must persist locally.
- Using the app requires an account; accounts are stored locally on the device.
- Login uses a unique email and a password (stored as a salted hash, never plain text).
- A self-registered account stays pending and cannot log in until the relevant project owner confirms it.
- Approval records the confirming project owner's id (`approved_by`).
- Roles are admin, project owner, and user, and they are cumulative: an admin can do everything a project owner and a user can do, and a project owner everything a user can do.
- Only an admin creates projects, assigns project owners, and manages roles.
- A project owner confirms new members of their own project and manages its tasks and assignments.

## 6. Constraints

- Offline-first: core functionality must work without internet access.
- Multiple user accounts stored locally on a single device; no backend server is required for the initial version.
- Keep the implementation simple and maintainable.
- Avoid unnecessary dependencies and architectural complexity.
- Do not introduce AI features until the core task planner works reliably.

## 7. Decisions Not Yet Finalized

The following require discussion before implementation:

- Whether tasks should also support categories alongside projects.
- Whether reminders and notifications belong in the first release.
- Whether the app needs manual backup and restore.
- Whether the main planner should show a daily view, weekly view, or both.
- Which priority levels and task statuses are needed.
- The final architecture, database, and state-management choices.
- How the very first admin account is created on a fresh install.
- Password recovery or reset without a backend (for example, admin resets passwords).
- Which events trigger email notifications (proposed: new sign-up, approval or rejection, task assignment).

Do not silently decide these questions if they materially affect the design.

## 8. Development Rules

- Inspect the existing repository before proposing changes.
- Reuse existing code and project conventions where appropriate.
- Propose architectural changes and wait for explicit approval.
- Do not implement unapproved features or install dependencies without approval.
- Keep changes small and test them independently.
- Report what was changed, what was tested, and any remaining issues.

## 9. Initial Development Objective

Start with discovery, not implementation.

Review this brief alongside the repository and proposed architecture. Identify missing requirements, important questions, risks, and the smallest useful next step.

Do not modify files or write application code during discovery. Present recommendations and wait for approval.

## Task Assignment

Each task has at most one assignee.

The assignee can be either:

- **A person** — identified by name, with a position such as Developer, Project Manager, or Business Analyst. Exactly one person is responsible.
- **A project** — the task is assigned to the project as a whole, meaning several people are affected; no single person is named.

Task rules:

- A task belongs to a project.
- A task can be assigned to that project as a whole (no individual assignee) or to one person from the project — never both at the same time.
- A person assignee must belong to the task's project.
- The assignee's position should be available when viewing the task.
- The assignee should be optional unless the user decides otherwise.
- The app should support assigning tasks to different people, not only the current user.

## Assignee Management

The application should provide a way to manage assignee information so the same person does not need to be entered from scratch for every task.

The exact management interface and data model must be proposed before implementation.

Each assignee belongs to a project via a `project_id` foreign key.

## Accounts and Roles

- The app opens on a login page; a sign-up page creates a new account.
- An admin creates each project and assigns its project owner.
- New users are created by an admin, by a project owner, or by self-registration.
- Approval records which project owner confirmed the account.
