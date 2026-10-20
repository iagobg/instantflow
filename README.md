# InstantFlow

PT-BR school workflow demonstration built with Phoenix LiveView and PostgreSQL. The visual identity comes from `design/visual-identity`; its example screens are visual references only.

## Current delivery

Sprint 00 provides one fictional organization, nine departments and staff accounts, invitation acceptance, password sign-in, revocable 24-hour sessions, a protected overview, and administrator-only staff invitations. Both themes use the supplied tokens and logos. Invitation delivery is explicitly simulated: an administrator shares a one-time code locally, valid for 48 hours. There is no outbound email.

Workflow execution, granular/overlapping role grants, parents, confidential records, files and finance belong to later sprints. This foundation is a demonstration, not a production student-data deployment. Password recovery, login throttling, MFA, and session cleanup are not implemented yet.

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

Open http://localhost:4000. Sign in as `admin@escola.example` with the password you supplied. Other fictional staff addresses are `secretaria`, `docente`, `coordenacao`, `financeiro`, `operacoes`, `ti`, `direcao`, and `orientacao`, each at `escola.example`. They share the seed password and have the staff profile. Parent accounts will be added with the parent portal in Sprint 04.

`PGHOST`, `PGPORT`, `PGUSER`, and `PGPASSWORD` override local defaults; see `.env.example`. Mix does not automatically load `.env`: export the variables in your shell. Set these before setup and checks if using an existing PostgreSQL instance. Production requires `DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_HOST`; `PHX_SERVER=true` enables the endpoint. Generate a production secret using `mix phx.gen.secret`. Production cookies require HTTPS and seeds refuse to run in production.

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
# Migration reversibility check, on a disposable development database only:
mix ecto.rollback --all
mix ecto.migrate
# Reset only the fictional local development database (removes all its records):
export DEMO_PASSWORD='choose-a-local-demo-password'
mix ecto.reset
```


The seed is repeatable and preserves existing users/passwords. To choose a new seed password, reset the disposable local database. `mix precommit` checks compilation warnings, unused lock entries, formatting and database/LiveView tests. CI also checks migration rollback/reapply, asset builds, and seeds. Database tests run in Ecto's sandbox; they do not constitute concurrency race evidence for later sprints.

## Conventions

Instants are stored in UTC; invitation expiry is formatted in PT-BR through PostgreSQL's IANA database in `America/Sao_Paulo`. Date-only fields will remain separate. Request IDs are included in baseline logs. Passwords, codes and tokens are filtered; SQL parameter logging and browser server-log streaming are disabled. `.local`, `.env`, dependencies and generated assets are ignored; build inputs remain in `assets/`. No real student records or external integration credentials are needed.

## Verification environment

See `sprint_plan/sprint_00.md` for delivery evidence. In the current WSL environment, tooling and an isolated PostgreSQL 16.15 cluster were extracted under ignored `.local/` because Docker and a system PostgreSQL server were unavailable. PostgreSQL listens on 127.0.0.1:55432; no system service was replaced. The documented Docker path remains the portable setup, and was not executed in this environment.

## Development plan

Start with `sprint_plan/sprint_index.md` and `design/index.md`. The functional plan determines screens; the example page in the visual identity does not determine functionality.
