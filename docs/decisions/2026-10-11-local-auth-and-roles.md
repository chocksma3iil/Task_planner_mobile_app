# Local Accounts with Three Roles

- Date: 2026-10-11
- Status: approved
- Context: the owner requested login and sign-up pages, per-project membership approval, and three roles (admin, project owner, user).
- Decision: accounts live in the local person (`assignees`) table — email, salted password hash, role, pending/active status. No backend. Admins create projects, assign owners, and manage roles and users. Owners confirm self-registered members of their own project and manage its tasks. Roles are cumulative (admin ⊃ owner ⊃ user). Pending users cannot log in.
- Reverses: "no account required" and "no multi-user functionality" (PROJECT_BRIEF.md §5–§6 updated). "No backend server" still holds.
- Still open: first-admin bootstrap on a fresh install; password recovery without a backend.
