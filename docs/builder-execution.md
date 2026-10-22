# Builder execution and participant contracts

Established 2026-10-21 in S09-T05 and extended through completed Sprint 09.
See [acceptance contract](builder-architecture-contract.md) and
[Sprint 09](../sprint_plan/sprint_09.md). The [participant/reference/document guide](participants-and-documents.md)
records completed migration/recreation acceptance and the later sprint gates.

## Ownership and dependencies

| Boundary | Implementation | Permitted dependencies |
|---|---|---|
| Portable definition | Definition, Diagnostics, CalculationContract, Interface, Schema, Interchange | Catalog contracts, standard/pure JSON libraries |
| Local installation | WorkflowCatalog.Bindings | Access vocabulary and tenant-owned departments/accounts inside an authorized transaction |
| Publication/drafts | WorkflowCatalog and Templates | Pure contracts, scoped mappings, immutable publication storage |
| Runtime coordinator | WorkflowRuntime | Tenant authorization, pinned contracts, closed capability contexts, receipts, audit and outbox |
| Participant state | Participants and Participants.Relationship | Tenant, membership ownership, catalog versions, runtime policy/audit/receipt protocol |
| Legacy authorization | WorkflowRuntime.LegacyAccess | Audited participant mappings for historical guardian links |

WorkflowCatalog.Capabilities descriptors record the closed identifiers, version 1,
owners/tables, dependencies/conflicts, declaration fields, symbolic binding groups,
guards, effects, projections and immutable-version migration policy. Participants
is an additive registered capability. Metadata does not grant authority or load
dynamic callbacks; concrete contexts enforce business invariants.

Calculations.Contract now delegates pure validation to
WorkflowCatalog.CalculationContract. AST checks protect the pure catalog boundary
and prohibit direct Enrollment/Incidents dependencies from migrated runtime,
policy and participant paths.

## Common transaction protocol

1. Validate the bounded envelope. Enter Tenant.transaction for runtime work or
   Tenant.authorize_change for relationship mutations.
2. Lock organization, shared/exclusive authorization gate, current user and
   membership, in that order. Resolve current grants.
3. Lock business rows in fixed order: runtime ticket then sections ordered by key;
   participant commands ticket then relationship.
4. Resolve the ticket's immutable version/declaration/bindings. Authorize against
   that snapshot and current membership/relationship state.
5. Look up the actor/operation/key receipt under those locks. Reauthorize replay
   and reject changed digests. Replay never applies effects again.
6. Validate expected revisions, inputs and guards. Apply effects, advance
   revisions, and write audit, durable refresh/outbox intent and receipt in the
   same transaction. A later failure rolls back every earlier effect.
7. Commit, then invalidate projections. Durable refresh recovers missed immediate
   broadcasts. External provider/runner work remains outside locks; asynchronous
   results retain their authorization/version/input fences.

BuilderTransactionTest forces the final outbox check to fail after finance effects:
balances, ticket, sections, audit and receipt remain unchanged. Retry commits once,
and replay after role revocation is denied. RuntimeRoleTest holds participant
revocation's exclusive gate until a queued save is waiting on another connection;
after commit, that save is denied. Neither proof uses sleeps.

## Binding and publication lifetime

Portable definitions carry symbolic roles, department/account references and
relationship declarations, never membership IDs or relationship rows. Imports
create unmapped drafts. Partial mappings may be saved; publication requires every
mapping to resolve within the current organization. Mapping resolution grants no
record access and never chooses a missing department/account automatically.

Shared definition errors identify paths such as modelo.transitions[0].required_fields
and modelo.sections[1].access[0].relationship. Editor review reports individual
missing/invalid selections at mapeamentos.roles.*, mapeamentos.departments.* and
mapeamentos.budgets.*. Direct publication retains :invalid_bindings for caller
compatibility; review obtains detail from the same Bindings.errors implementation.

Preview validates declarations/mappings without creating relationships.
Installation requires explicit mappings; rebinding means publishing a new immutable
version. Existing records/sessions retain that version's rules, account/department
IDs, interface and closing transition. Current membership/grant validity,
organization suspension and relationship verification remain live. Publication
cannot restore revoked authority.

The registry is version 1 under portable format 1.0. Future semantic changes need
an explicit compatibility/migration decision. Complete mixed-version projections
and composed-capability acceptance remain Sprint 11 work.

## Participant declaration and commands

Enable capabilities ["core", "participants"]. A declaration is portable:

```json
{
  "participants": [{
    "key": "customer",
    "label": "Cliente verificado",
    "kind": "external",
    "candidate_roles": ["customer"],
    "managers": [{
      "role": "verifier",
      "scope": "workflow_department",
      "department_binding": "front_desk"
    }]
  }]
}
```

candidate_roles references declared symbolic roles and their local mappings. It
controls who may be linked, independently of any record access. New publication
requires explicit eligibility; picker and create/verify commands share the same
scoped checks. The customer role in this fragment must be declared and mapped by
the enclosing definition/installation.

Kinds are requester, subject and external; they describe participation without
selecting example-specific behavior. Managers use declared roles under
assigned_department or workflow_department. Participant/guardian manager scopes
are rejected to prevent recursive verification authority.

Section/transition actors use scope participant, a relationship key and a symbolic
role. Both current bound role and verified relationship must match the exact
organization, process, ticket and membership. Administration alone grants no
protected-section access.

Participants.command accepts exactly operation (create/verify/revoke), ticket_id,
membership_id, relationship, expected_revision and key. Create requires revision 0
and inserts pending state; it never invites or verifies an identity. Verify
requires a declared manager and rejects self-verification. Verify/revoke require
the current relationship revision. Commands have bounded keys, at most 100
relationships per ticket, receipts, ticket revision advancement, manager-only audit
history and durable refresh intents.

The additive forward-only migration enforces tenant/process/membership ownership,
immutable association keys and tenant RLS. Revocation uses the exclusive
authorization gate; protected reads, saves and replay use its shared counterpart.

The typed editor creates relationship declarations and participant section access;
roles and departments use existing mapping controls. Import supports participant
transition actors, and transition edits preserve them. Imported assigned-department
manager semantics are preserved on label edits; the initial typed manager builder
creates fixed department mappings.

Generic record controls now manage pending/verified/revoked relationships.
External local identities use supported invitations without enrollment or default
staff grants. Directory and declared document fields use the same pinned contracts,
live policy gates, bounded authoring controls and revision/receipt/outbox protocol.
See the linked guide for full field declarations and supported target limits.

## Legacy allowlist and remaining gates

LegacyAccess now reads the reusable participant mapping and has no Enrollment
service dependency. The behavioral allowlist is PrivateDocuments.LegacyPolicy →
Enrollment.staff?/guardian? for historical fields without declared policy.
Enrollment.Document remains a storage-schema alias used by PrivateDocuments,
not behavioral dispatch. Historical guardian policies/URLs and immutable JSON
retain their behavior. Participant definitions reject guardian actors and require
declared file policies.

The additive backfill preserves guardian source IDs and audits mappings while a
transactional bridge synchronizes old invitation/verification/revocation writes.
Populated two-school forward migration and backup/restore pass. Existing student
section values are preserved without inventing identity links.
Full school portal replacement and richer generated experiences remain Sprints
10–11; current compatibility is explicit and tested.

## Incremental executable evidence

| Scenario | Fixture/test and supported setup | Remaining gate |
|---|---|---|
| Core-only | BuilderFixtures.core_definition; BuilderRecreationTest; import → map → publish → create/save/complete | Full recreation matrix |
| Equipment desk from blank definition | BuilderFixtures.equipment_definition and equipment_participant_definition; invitation, verification, scoped reference, correction, private release/resubmission, resource settlement, pinned publication | Parts/handoff and complete composed matrix in Sprint 11 |
| External service and independent copy | Participant, directory and declared-document fixtures/tests; verification/revocation, renamed contracts, generated record URLs, unrelated users denied | Rich participant projections in Sprint 10 |
| Core + finance | BuilderTransactionTest; late-effect rollback, replay, revocation | Explicit resets and complete composed matrix |
| Non-owner runtime login | RuntimeRoleTest and GuardianMigrationTest; independent queued write/reference/download races, RLS, populated backfill and pg_dump/restore | Full mixed-capability result matrix in Sprint 11 |
| Typed authoring | TemplatesLiveTest and declared-document LiveView test; field/relationship authoring, local mappings, generic participant management, upload/release/revocation | Rich projections and complete school replacement |
| Bounded configured projections | ProjectionsTest and GeneratedProjectionLiveTest; authorized SQL paging/counts, batched readable sections, non-creator participant work, removed-view pinning and hidden metadata denial; [contract and evidence](bounded-projections.md) | Configured dashboard expansion and Sprint 11 scale acceptance |
| Declared participant correction/document page | ParticipantPagesTest and ParticipantLiveTest; editor → local mappings → publication → generated entry/list/detail → correction/upload/release/resubmission; unrelated/subject denial, parent staff grant, revocation/reconnect and changed publication; [contract and architecture review](participant-pages.md) | Curated messages, synthetic draft-preview UI and complete school/equipment recreation |

[Local evidence](evidence/sprint09-local.json) identifies the working-tree base,
changed-source hashes and checks. All data is synthetic and databases are isolated.
