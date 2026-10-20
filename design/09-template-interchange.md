# Template import/export and LLM authoring

[Design index](index.md)

Status: proposed inclusion in Sprint 03 following the user's suggestion.

## Value and format

A portable contract enables sharing, backup, reviewable diffs, reusable school templates, and external LLM generation. It also requires the visual editor to represent the entire supported definition faithfully.

Use canonical declarative JSON with a published JSON Schema and semantic validator. Start with JSON only. Editor, importer, and seeded templates all use the same contract and publication checks.

## Versioning and contents

Distinguish `format_version` (compatibility), `template_version` (author metadata), and server-managed published workflow version. Stable symbolic keys identify stages/fields/roles; labels are PT-BR. `capabilities` declares required registered extensions. Unknown versions/capabilities fail clearly; never silently drop unsupported fields.

Export definition structure, public metadata, forms, transitions, role requirements, supported actions, and views. Exclude tickets, students, users, memberships, actual grants, comments, attachments, secrets, provider endpoints, and integration identifiers. Schema names may still disclose business practices; export requires a dedicated permission and contents preview.

Portable roles are symbolic requirements, not installed grants. Directory/domain references use symbolic bindings resolved locally. Imported keys cannot override built-in roles or another workflow's namespace.

## Import pipeline

1. Authorized administrator uploads JSON. Proposed limits: 1 MiB, depth 20, 100 stages, 500 transitions, 300 fields. Reject duplicate keys, unknown properties, malformed types, oversized expressions, and unsupported versions.
2. Validate JSON Schema, then references, reachability, terminal paths, field types, guards/actions, and supported capabilities.
3. Create an isolated draft, defaulting to a new workflow. Updating an existing workflow requires explicit target selection and a diff; never overwrite by name.
4. Resolve role/department/domain bindings to permitted local resources. Missing bindings block publication. Import cannot create users, grant membership, or execute actions.
5. Preview approval paths, sensitive sections, external visibility, financial actions, and mappings using synthetic data. Flag approval bypasses/excessive authority for review; heuristics cannot prove business correctness.
6. An authorized publisher explicitly publishes through normal validation and revision checks. Audit source metadata, content digest, mapping, actor, and resulting version.

Render imported labels/descriptions as escaped plain text. Embedded instructions cannot change policies or invoke tools. Future built-in LLM assistance, if added, must use this pipeline and cannot publish automatically.

## Compatibility and deliverables

Export a selected immutable version or explicitly marked draft. Canonical ordering supports diffs. Reimport creates a draft and requires mappings again. No mutable database IDs leave the system.

Ship JSON Schema, capability catalogue, examples, and guide for each supported format release. Define complete schemas for every field, guard, action, and view before format 1.0 is final. Migrations are explicit and tested; unsupported versions have actionable PT-BR errors.

The [example](examples/simple_approval.json) is a proposed subset, not an implemented format. Role requirements grant no authority. Sprint 03 must deliver the authoritative schema and fixture validation.

## Acceptance

- Editor → export → import → editor preserves supported semantics after local mapping.
- Externally generated valid content imports as an unpublished draft.
- Unknown actions/fields, executable handlers, malformed graphs, and unauthorized mappings fail safely.
- Import executes no notification, provisioning, financial transaction, or grant.
- Unresolved mappings prevent publication; exports contain no operational records/secrets.
- No provider-specific LLM dependency is required.
