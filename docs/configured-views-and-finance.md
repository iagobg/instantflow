# Configured views, explicit corrections and finance surfaces

Sprint 10 checkpoint, 2026-10-22. This extends the bounded query and participant
checkpoints. All definitions remain portable; local grants, accounts and records
are installation state.

## Views

The typed view editor and importer accept optional `visibility_roles`, `filters`
(up to ten scalar field references), `sort` (`field`, `direction`), `calendar_field`,
`urgency` (`field`, ordered choice `values`) and `assignment_section`.
Publication validates references/types, urgency choices, roles and named assignment
declarations. Attachments, directory references, long text and multi-choice values
are unsupported query keys and produce diagnostics.

SQL applies pinned record/view and section permissions before user filters,
counts, distinct filter choices, ordering and paging. Hidden query fields evaluate
to NULL and cannot contribute urgency counts or filter choices. Sorting uses typed
JSONB scalar values (UTC-normalized instants), NULLS LAST and descending ID as the
deterministic tie-breaker. The newest authorized version selects the overall sort
direction; each row resolves its sort field from its own pinned declaration.
Mixed version stage labels, columns and values retain pinned meaning.

Filter choices are distinct values actually present in authorized data, capped at
100 per declared filter. Totals/stage counts are pre-user-filter within an
authorized view; displayed totals are post-filter. Urgency counts include only
readable highest-priority values on nonterminal records, using pinned terminal
declarations. Named assignment metadata/filtering requires section read authority
or an explicitly declared assignment manager. It grants no support-note access.

Calendar rendering includes undated records. Civil dates remain dates. Instants
are formatted in one batch with the organization's IANA timezone; conversion does
not run once per cell in templates. Each page remains bounded to 25 records.

Generated process pages operate all these declarations. The incident compatibility
dashboard now selects declared urgency views rather than template keys and uses
the same bounded service. Independent workflow/role/section/stage names are
supported. Historical dashboard URLs remain compatibility entry points; generated
process routes are the primary authoring/operation path.

## Explicit correction effects

Transitions can declare:

```json
{"reset": {"sections": ["order", "delivery"], "invalidate_approvals": ["signoff"]}}
```

Both target lists name existing sections, are individually bounded to 100 and
must not overlap. Approval invalidation clears the declared approval section's
values and advances its revision; unrelated approvals and operational/confidential
sections survive. The stage revision also advances under the existing coordinator.
No destination name, field type or finance block selects reset targets.

New publication of a finance release to the initial stage requires an explicit
reset declaration. Example requisition/trip files declare their supported targets.
The pinned legacy adapter retains old inferred behavior only for historical
versions lacking declarations. Old versions can be cloned into repairable drafts;
publication requires the new explicit contract. Historical JSON is never rewritten.

Reset, reservation release, stage/section revisions, audit, receipt and outbox
intent share one transaction. Audit details name affected sections/approval targets
without copying cleared values. A late outbox failure rolls everything back.
Stale saves fail the existing stage/section revision checks; duplicate receipt
replay does not reset state twice. This adds no transition engine or expressions.

## Finance surfaces and authority

The `finance_setup` and `finance_summary` blocks require the existing finance
capability and `interface.finance`:

```json
{"account_binding": "shared_budget", "scope": "process", "view_roles": ["requester"]}
```

`process` summarizes reservations and posted spend only for currently authorized
records of that workflow, grouped by their pinned account. It deliberately supplies
no shared allocation/available balance. `shared_account` shows the explicitly bound
account's allocation/reservation/spend/available totals only when the viewer also
has existing account-level financial authority in that account's department.
Process access alone reveals no other process transactions.

Definitions reference symbolic budget bindings. Organization-owned accounts are
created by the existing administrator command, available in the editor and setup
block. Mapping/publication does not grant account authority. Allocation remains a
distinct `finance_allocator` command; reservation/posting/reversal and self-approval,
partial receipt, idempotency and audit guards remain unchanged. Explicit current
financial grants work independently of a base parent/external membership label.

New publication can map future records to another account. Existing commands and
holds keep their pinned account; process totals continue to include authorized
historical holds on that account. Summary/group and setup option queries are
bounded (100 groups/options), and generated pages reauthorize on finance and
permission invalidations. No payment provider, tax or general accounting is added.

The additive migration adds event audit details and immutable curated-outbox
snapshot columns for the next checkpoint, with tenant foreign keys. Historical
rows receive empty metadata; version JSON and existing business values are untouched.

## Executable evidence

- `configured_views_test.exs`: hidden sort/filter/urgency noninterference, live
  grant revocation, scalar filtering, typed/civil/instant/undated calendar behavior,
  independent-key named assignments and administrator support-note denial.
- `configured_views_live_test.exs`: typed editor → publication → generated filter UI.
- Existing `projections_test.exs`: uneven hidden/accessible populations, multiple
  pinned versions, stable authorized pagination and constant query/batch counts.
- `surfaces_and_resets_test.exs`: approval invalidation, unrelated preservation,
  stale saves, replay, late rollback, shared-account scope and pinned rebinding.
- `finance_surfaces_live_test.exs`: local account creation, binding/scope setup,
  explicit reset editing, publication and guarded generated allocation.
- Existing finance contention, self-approval, partial receipts, composition,
  confidential assignment and populated migration/restore regressions remain required.

Curated communication, participant preview and the complete school/equipment
recreation matrix are the next checkpoint. Full customer-volume measurement and
residual old read paths remain Sprint 11.
