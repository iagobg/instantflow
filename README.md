# InstantFlow

InstantFlow is a general-purpose, multi-organization workflow platform built with Phoenix LiveView and PostgreSQL, with a PT-BR interface. Organizations customize processes, forms, permissions, and live dashboards for their own operations. School workflows provide the initial demonstration of the platform's versatility. The visual identity comes from `design/visual-identity`; its example screens are visual references only.

## Current delivery

Sprint 05 adds shared-budget reservations, audited purchasing and reversals, partial receiving, field-trip prerequisites, live authorized budgets, calendar agendas and department assignments. Open **Orçamentos** and **Solicitações**. See [finance walkthrough and limits](docs/finance.md).

Sprint 04 adds invitation-only guardian access, a separate parent enrollment projection, quarantined private documents, school-local verification, department handoffs and simulated payment/provisioning retry. Open **Matrículas**. See [enrollment and private documents](docs/enrollment.md) for the demo walkthrough, limits and setup.

Sprint 03 delivers the workflow editor, revision-safe drafts, immutable publication, configured request tables/boards, JSON format 1.0 import/export, and a PT-BR authoring guide. Open **Modelos de fluxo** as a local administrator. See [editor and interchange](docs/template-editor.md) and the [authoring guide](design/workflow_authoring_guide.pt-BR.md).

Sprint 02 adds department-specific local profiles, restricted projections, authorized request tables/counts, independent section drafts, conflict comparison/reapply, advisory editing presence, and safe reconnect/revocation behavior. See [collaboration and permissions](docs/collaboration.md).

Sprint 01A established multiple isolated organizations. Global login, local memberships, organization-bound routes, RLS and composite ownership constraints are in place. Existing Sprint 01 records were preserved by a forward migration. See [operator setup and recovery](docs/organizations-operations.md) and [organization isolation](design/11-organizations.md).

Sprints 00 and 01 are implemented. Sprint 01 adds validated immutable workflow versions, guarded requests, typed section values, safe command retries, correction/rejection/cancellation history, and a durable simulated delivery outbox.

The demonstration includes Escola Horizonte and Escola Aurora. The same `admin@escola.example` account is an administrator in Horizonte and a collaborator in Aurora; `gestao@aurora.example` administers Aurora. Global sessions last 24 hours. Existing-account recipients sign in before accepting local invitations; credentials and other memberships are preserved. Both themes use the supplied tokens and logos. Invitation delivery remains explicitly simulated with one-time 48-hour codes and no outbound email.

The enrollment parent portal and private files are implemented. Confidential incident workflows belong to Sprint 06. This application is a demonstration, not a production student-data deployment. Password recovery, login throttling, MFA, and session cleanup are not implemented yet.

## Prerequisites and setup

Pinned runtime: Erlang/OTP 28.5.0.2 and Elixir 1.19.5 (OTP 28), recorded in `.tool-versions`. Phoenix, LiveView, Ecto and all transitive dependencies are pinned by `mix.lock`. The application uses PostgreSQL 16; `compose.yaml` pins 16.15 and exposes it on loopback port 55432.



```sh
asdf install
mix local.hex --force
mix local.rebar --force
docker compose up -d --wait
export DEMO_PASSWORD='choose-a-local-demo-password'
mix setup
mix phx.server
```

Open http://localhost:4000. Sign in as `admin@escola.example` with the password you supplied. Other fictional staff addresses are `secretaria`, `docente`, `coordenacao`, `financeiro`, `operacoes`, `ti`, `direcao`, and `orientacao`, each at `escola.example`. They share the seed password and have the staff profile. The seed adds fictional `responsavel.a@escola.example` and `responsavel.b@escola.example` accounts with independent verified enrollment links in each school. New accounts use the supplied seed password; existing passwords are preserved.

See `.env.example` for the separate runtime and migration credentials. The server uses `PGUSER=instantflow_runtime` and `RUNTIME_DB_PASSWORD`; operators use `MIGRATION_PGUSER`/`MIGRATION_PGPASSWORD`. `PGHOST` and `PGPORT` select the local server. Mix does not automatically load `.env`: export variables in your shell. Production requires a non-owner runtime `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST`; `PHX_SERVER=true` enables the endpoint. Only operator commands receive `OPERATOR_DATABASE_URL`. Production cookies require HTTPS and seeds refuse to run in production.

## Invite a colleague in the demo

1. Sign in as the administrator and open **Equipe e convites**.
2. Enter a fictional email, department and profile; generate an invitation.
3. Copy the code into **Ative sua conta** at `/convite` (use a separate private session for the invitee).
4. Enter a name and a password of 12–128 characters. Sign in using the invited email. Email, department and role are bound to the invitation, never accepted from the registration form.

The code is displayed once and stored only as a SHA-256 digest. Acceptance is transactional and locks the invitation row. Passwords use PBKDF2-HMAC-SHA256 with 600,000 iterations and random salts. Session tokens are random and stored as digests. Authentication is checked at HTTP entry, LiveView mount, and before live events; invitation commands re-read and lock administrator permissions. Logout invalidates the token and disconnects its LiveView sockets.

## Checks and local reset

```sh
mix precommit
mix assets.setup
mix assets.build
# Forward migration and full backup/restore rehearsal, in newly created isolated databases:
python3 scripts/rehearse_01a.py
```


The seed is repeatable and preserves existing users/passwords. Sprint 01A is forward-only: never reset or remove another school to accommodate singleton rollback. Follow the [operator recovery procedure](docs/organizations-operations.md). `mix precommit` checks compilation warnings, unused lock entries, formatting and tests. CI also checks a legacy forward migration, multitenant backup/restore, rollback refusal, asset builds and seeds. Ordinary regression fixtures use the SQL sandbox; dedicated runtime-role tests additionally use independent connections and real non-owner credentials.

## Conventions

Instants are stored in UTC; invitation expiry is formatted in PT-BR through PostgreSQL's IANA database in `America/Sao_Paulo`. Date-only fields will remain separate. Request IDs are included in baseline logs. Passwords, codes and tokens are filtered; SQL parameter logging and browser server-log streaming are disabled. `.local`, `.env`, dependencies and generated assets are ignored; build inputs remain in `assets/`. No real student records or external integration credentials are needed.

## Verification environment

See `sprint_plan/sprint_00.md` for delivery evidence. In the current WSL environment, tooling and an isolated PostgreSQL 16.15 cluster were extracted under ignored `.local/` because Docker and a system PostgreSQL server were unavailable. PostgreSQL listens on 127.0.0.1:55432; no system service was replaced. The documented Docker path remains the portable setup, and was not executed in this environment.

## Development plan

Start with `sprint_plan/sprint_index.md` and `design/index.md`. The functional plan determines screens; the example page in the visual identity does not determine functionality.

## Try the workflow runtime

Open **Solicitações** to create a request using the published approval fixture. The seed includes a draft owned by docente@escola.example. Fill and save **Resumo** and **Justificativa**, then submit for review. Sign in as financeiro@escola.example to review it. The first simulated notification deliberately fails; approval waits until the reviewer chooses **Tentar novamente** and its second attempt succeeds. Corrections, rejection and cancellation require explicit reasons. All effects and notifications are fictional.

The backend validates published definitions, required fields, actor scopes, typed guards, reviewed revisions and idempotency keys inside short transactions. Published versions, command receipts, history and delivery attempts have database immutability triggers. Tickets remain pinned when version 2 is published. A durable refresh intent exists for each mutation and simulated delivery result; the polling worker recovers a missing post-commit wakeup. Refresh invalidations contain only a ticket identifier. Delivery is at least once and never calls an external provider.

The current UI supports text, integer money, dates/instants, booleans and choices in authored templates. Directory values remain blocked. Private attachment values are proved against their organization, request, section and field; parent uploads are available through the enrollment portal. Requests use 25-row pages with authorized search, stage filters, exact scoped counts and configured views that hide unreadable fields. Sprint 03 verifies draft races and explicit publication using independent runtime-role connections; Sprint 02 covers section collaboration and permission revocation. Open an organization under `/o/horizonte` or `/o/aurora`; the global organization picker is `/organizacoes`.
