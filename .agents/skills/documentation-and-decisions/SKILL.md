---
name: documentation-and-decisions
description: Use when updating project documentation or recording an architectural, business-rule, or scope decision. Keeps AGENTS.md, PROJECT_BRIEF.md, and docs/ in sync and logs decisions under docs/decisions/.
---

# Documentation and Decisions

## Rules

- After approved changes, update the docs the change affects: brief for requirements, `docs/ARCHITECTURE_PROPOSAL.md` for direction and model, `docs/IMPLEMENTATION_PLAN.md` once a plan exists.
- Record each material decision as a dated file under `docs/decisions/` (context, options considered, decision, status). See `docs/decisions/README.md` for the format.
- Never present a proposal as approved. Drafts stay marked PROPOSED until the user explicitly approves.
- Keep docs compact: every line must earn its place for a future agent session. Delete stale claims instead of letting them rot.
- Documentation updates that change stated behavior or rules follow the same propose-and-approve workflow (see `interactive-development`).
