# Workflow engine

[Design index](index.md)

## Definition contract

Each version contains PT-BR labels/help text, stable stages, entry/terminal states, directed transitions, typed sections/fields, permission requirements, assignments, guards, actions, and view configuration. Editor and importer use this same model.

Each workflow/version belongs to one organization. Template installation copies a portable definition into the selected authorized organization and resolves local bindings; customer edits cannot mutate another organization's copy or a platform template. Keys/version numbers are local to their owning workflow/organization. No transition may target a foreign ticket, department, budget, script, or workflow version.

Initial fields: short/long text, integer, money, date, datetime, boolean, single/multiple choice, directory reference, attachment. Requiredness can vary by stage. Administrator-authored SQL, HTML, JavaScript, and Elixir are excluded.

Guards use bounded typed expressions: equality/comparison, presence, enumerated membership, all/any, attachment readiness, and registered domain checks. Limit size/depth and reject unknown references. Domain checks include budget availability and successful simulated receipt.

Actions are registered typed capabilities: assignment, simulated notification/provisioning, and finance operations. No arbitrary URLs or executable handlers. Each action has an idempotency policy.

For Sprints 00–07 this remains a closed registry. The planned [Python extension](10-python-automation.md) adds a separately isolated asynchronous action only after its readiness gate; it does not turn transactional guards into Python expressions. A required computation uses an explicit waiting stage and a fresh-result guard. Existing built-in guards remain authoritative.

## Editor

Edit “Etapas”, “Formulários”, “Permissões”, “Transições”, and “Visualizações”. Provide graph and keyboard-accessible list views, synthetic role preview, validation, and explicit “Publicar versão”. Preview grants no production access. Publication authority does not imply student-data access or unrestricted role grants.

Reject missing/ambiguous entry, unreachable stages, invalid references/types, dead ends without terminal status, and transitions without actors. Explicit correction/reopening cycles are allowed and visible in preview. Warn about unused fields and missing correction routes.

## Runtime semantics

- New tickets use the current published version; existing tickets remain pinned.
- Published definitions are immutable; active-ticket migration is outside this round.
- Draft editing uses revision checks.
- Stage changes occur only through transition commands.
- Recheck required fields, actor permission, guards, and reviewed revisions transactionally.
- Corrections carry a reason and recorded return target; resubmission returns to the requesting review stage.
- Rejection, cancellation, and reopening are separately authorized transitions with reasons.
- Editing approval-sensitive values invalidates approval or returns to review. Approved costs/itineraries cannot change silently.
- Returning to an earlier stage does not erase external intents. Record cancellation/reversal where supported.
- Failed notifications do not undo committed business state. Required provisioning/payment results keep tickets waiting until successful.

## Reuse gate

An administrator creates a workflow without code, clones a school template, adds a field/stage, restricts a transition, and publishes version 2 while a version-1 ticket remains usable.

Views support configured columns, filters, sorting, pagination, and scoped counts. Kanban maps stages to columns; calendar uses a configured date field and separately exposes undated items. Dragging proposes the normal guarded transition and cannot bypass required fields/reasons.

See [interchange](09-template-interchange.md) for portable definitions.
