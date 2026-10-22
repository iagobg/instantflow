# Declared participant pages

Implemented and reviewed locally on 2026-10-22 as Sprint 10's first participant
correction/document checkpoint. This extends the [bounded query foundation](bounded-projections.md).
The full Sprint 10 tasks remain open.

## Authoring and local setup

Declare relationships, candidate roles, section access and document policies using
the Sprint 09 controls. Invite external identities and explicitly verify their
record relationships. Eligibility to be selected as a subject never grants record
access. Bind portable roles and departments through the existing local mapping form.

In the page editor, enable **Página de participação declarada**, select the
visibility roles and projection audience separately, and select the released
fields, document fields, actions, status and history. Use the records block alone.
An independently configured example is
`BuilderFixtures.participant_page_definition()` (`repair_authorization`).

The portable declaration lives on a page:

```json
{
  "key": "my_packet",
  "label": "Minha documentação",
  "blocks": ["records"],
  "participant": {
    "visibility_roles": ["visitor"],
    "audience": [
      {"role": "visitor", "scope": "participant", "relationship": "claimant"}
    ],
    "fields": ["customer_details.description"],
    "documents": ["customer_details.evidence"],
    "actions": ["send_packet"],
    "status": true,
    "history": true
  }
}
```

The schema bounds visibility roles and audience entries to 30, ordinary fields to
50, document references to 20 and actions to 30. Publication checks declared roles,
actors, relationships, departments, fields, document policies and transition keys.
Unknown references, unsupported blocks, guardian actors and directory-reference
fields in this page produce validation errors. Directory setup stays in existing
staff controls; attachment fields use the separate document selector. Existing
imported actor scopes are preserved by the audience selector.

Participant pages require the participants capability. A document selector also
requires an attachment field with its declared policy and the existing document
capability validation. The page cannot make a field writable, bypass a stage,
release a quarantined document or approve a transition.

## Discovery, URLs and pinning

The process index adds an entry only when an authorized record exists for that
page. Participant discovery and counts use the bounded SQL projection service;
creation permission is not required. A subject-only relationship produces no
entry, record row or count. List pages contain only record IDs, the pinned page
label and explicitly selected status, ordered by descending ID in pages of 25.

Generated routes are organization- and process-bound:

- `/o/:organization_slug/processos/:workflow_id/participacao/:page_key`
- `/o/:organization_slug/processos/:workflow_id/participacao/:page_key/registros/:id`

Record URLs resolve the record's pinned version, including page, field, stage and
action declarations. A subsequent publication may remove the page and rename
fields/stages/actions without redirecting old records to the new definition.
An unknown record-page key falls back to the first authorized page from that
record's pinned definition and canonicalizes the URL. No authorized pinned page
means denial. A missing list-page key returns zero rows.

For workflow versions with declared participant pages, projection-only users
cannot use the generic request lists/views or staff record renderer to obtain a
broader projection. Old generic record URLs redirect to their authorized pinned
participant page. Staff workspace entry requires creation authority or explicitly
mapped `interface.access.view` roles, with record/section policies still applied.
This distinction uses declared authority, including scoped staff grants on parent
or external memberships; base membership labels do not select the participant UI.
Historical guardian/enrollment versions retain their existing compatibility routes.

## Reads, commands and protected state

Page admission requires visibility, projection audience and underlying record
discovery independently. Runtime policy intersects selected fields/documents with
current section authority. Server projections omit unselected values, local bindings,
participant identities, internal sections and arbitrary event/delivery payloads.
History contains at most 50 selected, authorized transition labels and timestamps;
it excludes actors, internal reasons and section changes. Documents return metadata
without content, bounded to 20 with active objects first. The existing document
quota bounds active objects; older rejected/deleted metadata can be truncated.

The renderer uses streamed collections and bounded retained forms. Field saves
merge only selected inputs into current section values, preserving unselected
fields. Existing stage/section revision guards reject stale drafts. Transition
adapters resolve current readable revisions server-side and still use the runtime's
ticket revision, actor, attachment-readiness and return-stage guards. Upload and
attachment association share one transaction and reuse private document receipts,
quarantine, type/size policy and the existing guarded save command. Duplicate
upload replay does not add another object or association.

Each operation reauthorizes under the tenant's shared authorization gate. Revocation
uses its exclusive counterpart. Permission refresh and reconnect re-project state;
lost access clears forms, drafts, action/upload forms, pending uploads and protected
streams before redirecting to the process index. Narrower field/upload authority
also prunes retained state. Broadcasts carry invalidation only; the renderer obtains
authorized data again instead of accepting pushed record contents.

## Checkpoint evidence and architecture review

`participant_pages_test.exs` and `participant_live_test.exs` exercise:

- Editor page controls, local role/department mapping and publication through UI.
- Independent repair authorization, invited participants and verified relationships;
  two unrelated participants have separate records, and a verified subject has none.
- Field correction, hidden-field preservation, document upload, readiness rejection,
  independent release, resubmission and another correction.
- Visibility distinct from audience/record authority, a parent with an explicit
  teacher grant, grant removal and relationship revocation.
- Generic list/view denial, legacy record-link redirect, protected draft/pending
  upload revocation, denied reconnect and file download.
- A second publication removes the page and changes field/stage/action keys;
  reconnect still renders the old record and unknown-page fallback uses its pinned page.

Architecture review found and corrected two issues before broader expansion:

1. Generic request lists/views could bypass the narrower participant projection.
   They now require declared staff workspace authority for these pinned versions;
   old record URLs route through the participant projection.
2. Runtime page admission had entered the catalog module. It now lives in
   `WorkflowRuntime.ParticipantPolicy`; catalog validation remains pure.

The catalog owns declaration validation, the runtime policy owns admission,
the projection service owns bounded list selection, and the participant context
owns bounded detail projections and adapters to existing commands. The LiveView
owns forms/streams/navigation and performs no database queries. No generic path
dispatches through Enrollment or Incidents. `Enrollment.Document` remains the
documented storage-schema alias. `participant_boundary_test.exs` guards these
dependencies. Existing command transactions, capability owners and outbox protocol
remain authoritative.

The [checkpoint evidence](evidence/sprint10-participant-checkpoint.json) records
validation and source hashes. Fixtures are synthetic and use supported installation
and scoped commands; no schema migration or deployment is required.

## Remaining work

This checkpoint covers the first correction/document experience, not all of T01.
Curated messages and recipient-visible delivery status remain T04 work. A dedicated
synthetic participant draft-preview interaction remains open; this increment adds
no preview that reads live records or simulates permission by hiding browser blocks.
Full school/equipment recreation remains pending. Next in the sprint sequence are
the configured filter/sort/calendar/urgency surfaces and explicit finance resets.
