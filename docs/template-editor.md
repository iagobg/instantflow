# Workflow authoring and portable format 1.0

Local administrators open `/o/:organization_slug/modelos`. They can create a process, clone a published version, edit metadata, stages, transitions, roles, sections, typed fields, section access, bounded guards/actions, assignment bindings and table/board views. The SVG diagram is accompanied by native keyboard-operable forms and a complete item list. No drag-only interaction or executable script editor is included. Grouped guards also have a declarative JSON control; the full definition can be edited through the same validator.

Draft saves compare the observed revision under a row lock. Conflicts preserve the proposed definition, compare it with current server data, and require explicit reload/review. Publication compares both draft revision and base published version. Cloning a version preserves its local mappings; importing always clears mappings. Publishing creates a new immutable version and seals the draft. Active requests retain their existing version.

The diagram follows a top-to-bottom layout with aligned main stages, labelled right-angle connectors, and separate outer lanes for return, cancellation and long-distance transitions. Solid purple lines distinguish forward transitions from dashed alternative paths. The keyboard-accessible stage selector highlights incoming/outgoing connections while dimming unrelated paths and centers the selected stage within the scrollable panel; this does not save the draft or clear pending form edits. Larger diagrams scroll within the panel, and reduced-motion preferences disable animated panning.

## Import and export

The authoritative artifacts are [schema](../priv/templates/workflow-1.0.schema.json), [capability catalogue](../priv/templates/capabilities-1.0.json), [PT-BR authoring guide](../design/workflow_authoring_guide.pt-BR.md), and [examples](../design/examples). Format 1.0 is final for this increment. Existing immutable `1.0-draft` versions remain readable and clonable; exports normalize that spelling to `1.0`. New imports accept only `1.0`; unsupported versions fail explicitly, with no silent property removal.

The importer checks the 1 MiB limit and depth before decoding, rejects duplicate keys, validates the delivered JSON Schema vocabulary, then validates references, typed guards, reachability and terminal paths. This is the same validator used by publication; editing permits structurally valid drafts with unfinished graphs. It rejects unknown actions, capabilities, properties and inline code. The schema evaluator is intentionally limited to the keywords present in the delivered schema; it is not a general-purpose JSON Schema service. Its vocabulary is covered by tests.

Import defaults to a new workflow, fails on an existing key, and never updates by name. Selecting an existing workflow is explicit and requires its symbolic key to match. A new independent copy may explicitly select a new key. Organization, actor and target ownership come from authenticated scope, never the file. Bindings are validated against local resources, including for people who administer multiple organizations. Import neither invokes the runtime nor creates users, grants, tickets, deliveries or other business effects.

Export is an explicit administrator-only command, separately authorized from ordinary request access. Users review definition contents before downloading JSON; drafts are marked in the preview and download filename. Exports include only the allowlisted declarative definition, never local department IDs, bound roles/grants, tickets or operational records. Canonical JSON sorts object properties and preserves collection order. A SHA-256 digest identifies the content; source digest, publication mappings, actor and resulting version are kept in append-only tenant-scoped audit history. User-authored labels and rules can disclose business practices and must be reviewed.

## Safety and operating boundaries

`workflow_drafts` and `template_events` use non-owner runtime-role RLS, tenant ownership FKs, and immutable organization ownership. Composite ancestry constraints bind drafts to versions in the same workflow and organization. Published drafts and template events are immutable. Fresh authorization is checked on each command and export; live sessions also revalidate role changes. Configuration authority provides no implicit request access.

Role previews use only the definition and local configuration. They contain no real records or user lists. Configured request tables/boards project each ticket's pinned definition through current section permissions; grant revocation removes protected columns and values on refresh. Views use the existing 25-row request pages and filters. Table/board type changes within a workflow should use a new view key for clarity when old pinned definitions coexist.

Directory references remain reserved declarations with fail-closed non-null values. Sprint 04 adds tenant-owned private attachments, verified `guardian` access, fixed `workflow_department` scopes, transition department handoffs and `simulate_payment`. The school parent projection remains a separate owning context; importing a template creates no guardians, files or real integrations. Python and real payments remain unsupported. See [enrollment operations](enrollment.md). Scalar and composite guards are bounded; this increment does not execute customer code.

## Verification

- `test/instantflow/workflow_catalog/templates_test.exs`: revision conflicts, publication pinning, independent imports, audit metadata, dual-administrator tenant isolation, forbidden mappings and stale/forged authority.
- `test/instantflow/workflow_catalog/interchange_test.exs`: shipped examples, schema vocabulary, malformed JSON, duplicate keys, size/depth bounds, unknown properties/capabilities/actions, nested guard preservation and editor round trips.
- `test/instantflow/workflow_catalog/views_test.exs`: restricted columns, grant revocation, version-pinned views.
- `test/instantflow_web/live/templates_live_test.exs`: native forms from creation through publication, export preview, uploads/import, clone/review, conflicting editors and session revocation.
- `test/instantflow/runtime_role_test.exs`: deterministic overlapping draft saves/publications through independent non-owner connections, single accepted revision, one publication event, tenant RLS and pinned tickets.

Run `mix precommit` and `mix assets.build`. Apply migrations with the operator repository; the migration is forward-only. Existing records and immutable workflow versions are preserved.
