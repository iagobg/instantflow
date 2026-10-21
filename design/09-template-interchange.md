# Template import/export and LLM authoring

[Design index](index.md)

Status: confirmed by the user and implemented in Sprint 03. See [delivery and operating details](../docs/template-editor.md).

## Value and format

A portable contract enables sharing, backup, reviewable diffs, reusable templates across sectors, and external LLM generation. The initial examples use school processes. It also requires the visual editor to represent the entire supported definition faithfully.

Use canonical declarative JSON with a published JSON Schema and semantic validator. Start with JSON only. Editor, importer, and seeded templates all use the same contract and publication checks.

## Versioning and contents

Distinguish `format_version` (compatibility), `template_version` (author metadata), and server-managed published workflow version. Stable symbolic keys identify stages/fields/roles; labels are PT-BR. `capabilities` declares required registered extensions. Unknown versions/capabilities fail clearly; never silently drop unsupported fields.

Export definition structure, public metadata, forms, transitions, role requirements, supported actions, and views. Exclude tickets, students, users, memberships, actual grants, comments, attachments, secrets, provider endpoints, and integration identifiers. Schema names may still disclose business practices; export requires a dedicated permission and contents preview.

Portable roles are symbolic requirements, not installed grants. Directory/domain references use symbolic bindings resolved locally. Imported keys cannot override built-in roles or another workflow's namespace.

Import destination comes from the authenticated active organization, never file-supplied organization IDs. Resolve all bindings inside that organization and reject foreign resource IDs even if the importing user belongs to both tenants. Sharing a portable definition is explicit export/import by authorized users; it never shares live data or links future updates. Platform templates install as independent copies. Imported content cannot create/switch organizations or grant membership.

## Import pipeline

1. Authorized administrator uploads JSON. Proposed limits: 1 MiB, depth 20, 100 stages, 500 transitions, 300 fields. Reject duplicate keys, unknown properties, malformed types, oversized expressions, and unsupported versions.
2. Validate JSON Schema, then references, reachability, terminal paths, field types, guards/actions, and supported capabilities.
3. Create an isolated draft, defaulting to a new workflow. Updating an existing workflow requires explicit target selection and a diff; never overwrite by name.
4. Resolve role/department/domain bindings to permitted local resources. Missing bindings block publication. Import cannot create users, grant membership, or execute actions.
5. Preview approval paths, sensitive sections, external visibility, financial actions, and mappings using synthetic data. Flag approval bypasses/excessive authority for review; heuristics cannot prove business correctness.
6. An authorized publisher explicitly publishes through normal validation and revision checks. Audit source metadata, content digest, mapping, actor, and resulting version.

Render imported labels/descriptions as escaped plain text. Embedded instructions cannot change policies or invoke tools. Future built-in LLM assistance, if added, must use this pipeline and cannot publish automatically.

Python is not a supported capability in Sprints 00–07. Do not relax unknown-action rejection to reserve it. When the [isolated extension](10-python-automation.md) ships, add a versioned capability for symbolic references to separately reviewed immutable scripts, input/output mappings, and limits. Workflow files contain no inline Python. Imports require local script-version binding and cannot activate code. Script source exchange, if later needed, is a separate review/import operation; the current LLM workflow guide must not generate executable scripts.

## Compatibility and deliverables

Export a selected immutable version or explicitly marked draft. Canonical ordering supports diffs. Reimport creates a draft and requires mappings again. No mutable database IDs leave the system.

Ship JSON Schema, capability catalogue, examples, and guide for each supported format release. Define complete schemas for every field, guard, action, and view before format 1.0 is final. Migrations are explicit and tested; unsupported versions have actionable PT-BR errors.

The [simple example](examples/simple_approval.json) and [typed example](examples/typed_approval.json) validate against the delivered [schema](../priv/templates/workflow-1.0.schema.json) and [capability catalogue](../priv/templates/capabilities-1.0.json). Role requirements grant no authority. Existing immutable `1.0-draft` versions are normalized to `1.0` when cloned/exported; new imports require `1.0`.

## Acceptance

- Editor → export → import → editor preserves supported semantics after local mapping.
- Externally generated valid content imports as an unpublished draft.
- Unknown actions/fields, executable handlers, malformed graphs, and unauthorized mappings fail safely.
- Import executes no notification, provisioning, financial transaction, or grant.
- Unresolved mappings prevent publication; exports contain no operational records/secrets.
- No provider-specific LLM dependency is required.
