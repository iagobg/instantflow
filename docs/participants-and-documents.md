# Participants, scoped references and private documents

Sprint 09 implementation and synthetic acceptance, 2026-10-21; review corrections, 2026-10-22.
See [builder execution](builder-execution.md), [sprint tracking](../sprint_plan/sprint_09.md)
and [revision/environment evidence](evidence/sprint09-local.json).

## Configure and operate a process

1. As an organization administrator, use **Equipe e convites** to invite a
   **Participante externo**. Activation uses the existing one-time simulated
   invitation code. This creates a local external membership with no staff grants,
   enrollment, relationship verification or default staff creation authority.
   Existing school parent invitations retain their enrollment-bound contract.
2. In **Modelos de fluxo**, declare symbolic external and verifier roles, then add
   a **Relacionamento verificado**. Choose its kind, eligible candidate roles and
   verifier department binding. Candidate roles are independent of section access.
   Map symbolic roles explicitly: for example customer → external and verifier →
   an existing locally granted staff role. Administration alone does not confer
   protected record access.
3. Add section access with scope **Participante verificado** and the relationship
   key. Section read/edit stages govern record data, uploads and downloads.
   Add a directory field or private-document field as described below, then
   review local mappings and publish.
4. On the common record page, an explicitly declared relationship manager uses
   **Relacionamentos de participantes**. Search returns at most 25 active local
   accounts eligible for the relationship's declared candidate roles. Add a pending link,
   verify the real relationship separately, then choose **Verificar relacionamento**.
   Pending links grant no access. Managers can revoke or explicitly reverify a
   relationship using its current revision.
5. Participants use the existing generated record URL:
   /o/:organization/processos/:workflow_id/registros/:ticket_id.
   Each request/event rechecks the live local scope against the record's pinned
   definition. Unrelated accounts and copied processes cannot reuse the relationship.

Invitations authenticate identities; relationship verification establishes their
connection to one record. Neither action substitutes for the other. Only current
bound roles plus current verified relationships authorize participant-scoped data.
Management controls do not become a global account directory or grant data access.

Each new relationship declaration must list 1–30 unique symbolic `candidate_roles`,
for example `"candidate_roles": ["customer"]`. These keys reference
`role_requirements` and resolve through the installed role bindings; definitions
contain no local account IDs. An active membership's base role or current local
grant may qualify it. Search is restricted to this organization, excludes the
acting manager, and returns at most 25 matches for a 100-character query. The same
eligibility query guards create and verify, including receipt retries under the
authorization gate. Losing eligibility blocks verification/retries; revocation
remains available. Eligibility by itself grants no section, transition or file access.

A subject-only relationship can therefore select a local authenticated subject
without giving that subject any actor permissions. Add a subject directory field
and manager permissions; do not add subject read access merely to populate a picker.
Missing, empty or undeclared candidate roles produce a publication diagnostic at
`modelo.participants[i].candidate_roles`. Drafts may leave the list incomplete.
Previously pinned Sprint 09 publications without this field retain their original
inferred picker roles, now enforced for create/verify too. Clone and explicitly set
candidate roles before republishing; historical JSON and bindings are not rewritten.

For definitions declaring participants, mapped roles and scopes also govern staff
authority for parent/external base memberships. A teacher grant in the configured
department may authorize management or document review; a participant relationship
alone cannot. Creation and its discovery use the same current-role decision.
Historical definitions without participants retain the named `LegacyAccess`
parent/guardian compatibility path, evaluated against each ticket's pinned version.

## Reference declaration

A configured field stores one relationship ID:

```json
{
  "key": "contact",
  "label": "Contato verificado",
  "type": "directory_reference",
  "reference": {
    "target": "participant",
    "relationship": "customer",
    "cardinality": "one"
  }
}
```

Supported targets are participant and subject. A subject target requires a
relationship declared with kind subject; this increment supports authenticated
subjects represented by local memberships, not anonymous directory people.
Both targets reference verified record-local relationships, not global user IDs.
Definitions/export contain symbolic contracts; local membership/relationship IDs
exist only in installed data and submitted record values.

Managers may select verified members of the configured relationship. Other field
editors may select only themselves, and only when independently authorized for that
section. A stored reference grants no target record/file access.

The common form provides authorized substring search bounded to 100 characters,
25 results and, when needed, one additional authorized current selection.
Inactive users/memberships, revoked/unverified links and foreign records/processes/
organizations are excluded. Saving a stale or forged ID fails server-side.
Transitions reject stale non-null references until an authorized editor clears or
replaces them. Revoked labels become unavailable rather than exposing a live name.
Old unconfigured directory fields remain null-only and disabled until explicitly
configured; existing text student names are not converted into identity claims.

## Private-document declaration

Enable documents and configure each attachment:

```json
{
  "key": "evidence",
  "label": "Comprovante",
  "type": "attachment",
  "document_policy": {
    "reviewers": [{
      "role": "verifier",
      "scope": "workflow_department",
      "department_binding": "front_desk"
    }],
    "max_bytes": 4096,
    "media_types": ["application/pdf"]
  }
}
```

Section edit policy authorizes upload/deletion; section read policy independently
authorizes metadata and ready-file downloads. Reviewers also require section read
permission, a declared internal actor scope, current roles/assignment and an identity
different from the uploader. They need not be able to edit participant fields.
Supported reviewer scopes are assigned_department, workflow_department and assigned_user.
Named confidential assignment remains authoritative; administration grants no bypass.

Policies may narrow the existing global 5 MiB PDF/PNG/JPEG envelope. Uploads enter
quarantine. Manual review checks format, size, digest, expiry and current authority.
Required attachment fields cannot advance until ready. Rejection/deletion removes
content. Downloads use the existing private authenticated endpoint with no-store
headers and reauthorize every request. Revocation clears protected forms/streams
and invalidates old download URLs, finalization attempts, saved claims and retries.

Declared upload/review/delete mutations advance the ticket revision and atomically
write audit, outbox refresh and durable receipts. APIs accept a stable optional
command key; UI operations supply keys. Same-key replay reauthorizes current
permissions and returns current object metadata without repeating effects.
Changed payloads fail with idempotency_mismatch. Legacy file APIs keep their old
receipt behavior; they do not acquire new historical receipts during migration.
Integrity checks and manual release remain synthetic demonstrations, not malware scanning.

## Ownership inventory and legacy mapping

| Existing concept | Current ownership and compatibility |
|---|---|
| Global account/invitation | Identity; local membership role is distinct from verified relationships |
| Requester | Pinned ticket requester_id; requester scopes do not imply a participant relationship |
| Guardian | GuardianLink → audited ticket_participants mapping; legacy writes synchronize both in one transaction |
| Student | Existing enrollment section values are preserved; no separate student identity table existed to infer/backfill |
| Subject/external participant | Declared kind and verified record-local membership relationship |
| Counselor/department assignment | Existing assignments and current grants remain authoritative |
| Discovery/history | Common policy projects readable sections and permitted events; list/count boundaries reauthorize |
| Files | PrivateDocuments owns private bytes/commands; Enrollment.Document remains the compatible storage schema |
| Delivery | Durable generic refresh intent; no document bytes or protected section values are copied into notifications |

The backfill migration preserves guardian IDs in legacy_guardian_link_id with a
tenant FK and unique immutable association. Active verified, active pending and
revoked states map separately. Historical missing verifier attribution remains
missing; the migration does not invent an actor. Organization audit events record
each initial mapping and subsequent synchronized revision.

A database trigger synchronizes legacy invitation acceptance and verification/
revocation into the reusable model. It rejects ownership moves. Generic participant
commands cannot mutate legacy mappings; operators use the original enrollment
commands until the full replacement gate. LegacyAccess reads the reusable mapping
instead of calling Enrollment for authorization.

The remaining behavioral allowlist is PrivateDocuments.LegacyPolicy →
Enrollment.staff?/guardian? for unconfigured historical document fields only.
Participant definitions require explicit document policies and never enter that
legacy branch. Historical JSON, versions, tickets, links, file IDs/bytes, receipts
and history are not rewritten.

## Forward migration and recovery

Apply the generated additive migrations with operator credentials during the
normal coordinated migration window. The guardian backfill serializes against
guardian writes; FORCE RLS is restored within the same migration transaction.
Runtime credentials remain non-owner. Migration down is deliberately refused.

Reproduce the populated preservation/recovery acceptance with:

```sh
mix test test/instantflow/guardian_migration_test.exs
mix test test/instantflow/participant_directory_test.exs
mix test test/instantflow/declared_document_policy_test.exs
mix precommit
mix assets.build
```

The guardian test creates two populated synthetic organizations in a disposable
database at the previous schema, compares historical rows after migration, performs
pg_dump/pg_restore into another disposable database, compares recovered rows, and
downloads private files using non-owner runtime credentials. Revoking one school's
relationship after restore preserves the other school's access. It also verifies
post-upgrade invitation synchronization and rollback refusal.

Recovery uses a coordinated backup and the matching application release in an
isolated destination, then validates mappings, audit, authorization and private
downloads before operator-directed cutover. Do not reset tenants or rewrite
published definitions as a migration workaround. This evidence establishes local
synthetic preservation, not customer recovery objectives or tenant-selective restore.

## Acceptance evidence and handoff

BuilderFixtures installs via supported import, local mapping and publication.
The independently configured equipment desk uses external invitation/acceptance,
relationship commands, a scoped reference, renamed private document fields,
correction/resubmission and resource settlement. Its unrelated invitee gets no access.
LiveView tests exercise typed authoring, relationship management, reference
search/save, external upload, independent review and revocation through common URLs.
Context tests cover copied processes, two organizations, differently privileged
shared identities, exports, stale edits, receipts and denied file claims.
Independent real runtime connections verify revocation fences a queued protected
save, a stale reference save and a private download.

Sprint 10 still owns richer participant projections, configured dashboards,
explicit finance correction resets and curated communication. Sprint 11 owns full
school-example replacement, composed/mixed-version and scale acceptance.
Pilot activation retains Sprints 12–14 gates.
