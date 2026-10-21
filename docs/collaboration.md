# Local permissions and collaboration

Sprint 02 extends the tenant boundary with department-specific grants and section-aware collaboration. Use synthetic records for this demonstration.

## Local profiles

An administrator can add or remove teacher, admissions, head, finance, operations, IT, dean and counselor profiles in **Equipe e convites → Permissões por departamento**. Each grant belongs to one local membership and one department in the same organization. A role granted in department A cannot borrow department B from another profile. The original admin/staff profile and primary department remain compatible with published Sprint 01 definitions; definitions explicitly bind symbolic roles to supported local profiles. A new grant has an effect only where a definition binds that profile.

Administrators manage configuration and grants; record visibility still requires the section's explicit role and relationship policy. Sections accept internal/restricted classifications with explicit ACLs. The classification label alone grants no access. Reads project only readable section definitions/values, visible history and related delivery intents. Transitions may use history_visibility=actors to restrict their history reason and delivery projection to eligible actors. Workflow guards/actions and local role mappings are excluded from request summary/detail projections.

Finance-sensitive transitions declare finance_sensitive=true. Their requester cannot execute them, even when that person also holds a reviewer or finance role. No override exists in this increment. Existing immutable versions are not rewritten; publish a new version to use new policies.

## Editing and review

Every section has its own revision; a separate stage revision protects stage-dependent edits. Saving one section preserves other authorized drafts. An update to a clean section appears on refresh. An update to a dirty section retains its draft and offers **Revisar alterações**, comparison with saved values, **Reaplicar minhas alterações**, and discard. Reapplying adopts a fresh observed revision and command key; the user still explicitly saves. A subsequent race can produce another conflict.

Transitions compare the reviewed request revision and readable section revisions. Remote changes require explicit renewed review; dirty drafts block transitions. Submitted commands reuse their key when retrying the same payload. Recovering a form restores its observed revisions/key and values but never automatically submits it. Pending labels prevent accidental repeated clicks. Offline command buttons and submit/click handlers remain disabled until reconnect reconciliation completes.

Drafts are in memory and the current LiveView form only. They are not stored in localStorage, browser databases or server draft tables. A full browser reload/navigation can discard them. Losing section edit permission removes its draft; losing record/membership access clears protected data and redirects. Other authorized section drafts survive a local grant change.

Presence is advisory and never locks a form or authorizes a command. Heartbeats run every 15 seconds, expire after 45 seconds, and contain only local membership, section and timestamp metadata. Names are resolved only after current viewer/participant checks. Presence process monitoring also removes departed sessions. Hidden sections do not expose participant names.

## Tables and reconciliation

Requests use explicit search/stage filters, exact authorized stage counts, stable descending ID order and 25-row pages. The implementation evaluates policy over candidate summaries before computing counts/pagination, so the former 100-row pre-authorization cap cannot hide matches or skew counts. This is a correctness baseline; the proposed ten-organization/10,000-ticket performance target remains unmeasured until Sprint 07. Large deployments need measured query work before release.

Subscriptions are established before the first read. Detail events identify only their organization/ticket; dashboard invalidations have no record IDs or payload and go only to local recipients with discover permission. Clients requery current state, making duplicates/out-of-order events harmless. Outbox polling, reconnect, 15-second connected heartbeats and 30-second server reconciliation recover missed events. Every read/command independently checks current access. A missed permission invalidation can leave the previous display visible until reconciliation; it cannot authorize a subsequent protected refresh or command.

## Transactions and migration

Lock order is organization → authorization advisory gate → actor user → local membership → workflow/ticket → ordered sections → receipts/outbox. Commands/reads take the shared organization authorization gate. Membership and grant changes take it exclusively before locking any actor/target rows. A command already holding the shared gate finishes before revocation; a command queued behind committed revocation sees current permissions and fails. Do not perform online permission changes through raw SQL outside these APIs. Operator suspension retains the organization row lock boundary from Sprint 01A.

Apply the additive migration using operator credentials:

```sh
mix ecto.migrate -r Instantflow.OperatorRepo
mix assets.build
mix precommit
```

The new grant table has non-null ownership, composite local membership/department foreign keys, RLS USING/WITH CHECK and immutable organization ownership. It adds no default grants and changes no published definitions or records. Development checks migration versions with SELECT-only access; the runtime does not create schema tables. Restart the server when upgrading so the presence supervisor starts. Restore a coordinated backup to roll back; do not drop tenant records.

Tests retain the existing tenant/session regressions and add independent non-owner database races with lock barriers, multi-session LiveView editors, restricted projections/counts/events/presence, local grant management, and disconnected draft recovery. See [Sprint 02](../sprint_plan/sprint_02.md) for evidence. Production readiness, guardian policy, files and Python execution remain separate later work.
