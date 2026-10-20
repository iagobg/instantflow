# Sprint 00 — Foundation

[Sprint index](sprint_index.md) · Status: Done · Dependencies: none

Goal: reproducible Phoenix application shell and identity foundations.

Historical scope: delivered for one organization. Its completion evidence is unchanged; the later multi-organization requirement is implemented in [Sprint 01A](sprint_01a.md), not retroactively claimed here.

## Tasks

- [x] S00-T01 Bootstrap pinned compatible Elixir/Phoenix/LiveView/Ecto/PostgreSQL and developer setup.
- [x] S00-T02 Add organization, departments, accounts, invitations, memberships, and sessions.
- [x] S00-T03 Add PT-BR localization, layout, timezone formatting, accessible forms/errors.
- [x] S00-T04 Add fictional seed accounts and documented local reset.
- [x] S00-T05 Configure checks, migration validation, secret handling, and baseline logging.

## Acceptance criteria

- Fresh setup can migrate, seed, start, and run documented checks.
- Invited staff authenticate; unauthenticated users cannot reach internal screens.
- Navigation, authentication failures, validation, and accessible labels are PT-BR.
- No secrets or real student data are committed.
- UI explicitly identifies the simulated demonstration environment.

## Progress

Actual start / finish: 2026-10-20 / 2026-10-20  
Evidence:
- Application, runtime pins and dependency lock: `../mix.exs`, `../mix.lock`, `../.tool-versions`.
- Identity migration and contexts: `../priv/repo/migrations/20261020180524_create_identity.exs`, `../lib/instantflow/identity.ex`.
- PT-BR screens, tokens and timezone rendering: `../lib/instantflow_web`, `../assets/css`, `../lib/instantflow/local_time.ex`.
- Fictional seeds and local setup/reset instructions: `../priv/repo/seeds.exs`, `../README.md`.
- Checks: `mix precommit` passed with 18 tests; fresh migrate, rollback/reapply, seed rerun and assets build verified against isolated PostgreSQL 16.15 on WSL.
- Browser smoke: administrator sign-in, protected overview, staff listing and narrow-width layout; light and dark themes inspected.
- CI configuration: `../.github/workflows/checks.yml` (authored locally; remote CI has not run).

Remaining limitations: no production identity hardening, password recovery, parent accounts or granular role grants. Portable Docker setup was documented but not exercised here; local PostgreSQL was used. Detailed concurrency and revocation broadcast tests follow in Sprint 02.  
Blockers: none recorded.  
Handoff: identity foundation; detailed grants follow in Sprint 02.
