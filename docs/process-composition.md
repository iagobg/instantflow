# Organization-owned processes and generated interfaces

Updated: 2026-10-21. Local implementation; customer launch gates remain open.

## Intended model

An organization owns process definitions. A published, immutable process version declares fields, sections, access, stages, transitions, views and its interface. Creating another process does not require adding an Elixir module, controller or router entry. An example is definition data that can be copied, edited, reviewed and published in the normal editor.

The main workspace lists the organization's available published processes, based on the user's mapped roles. It does not infer an industry from an organization name or install school/restaurant modules automatically. Drafts do not appear as runnable processes. Public login and home language are organization-neutral.

## Generated URLs and UI

- /o/<organization>/processos lists installed processes.
- /o/<organization>/processos/<workflow_id> opens the first declared page.
- /o/<organization>/processos/<workflow_id>/p/<page_key> renders the blocks declared for that page, in declaration order.
- /o/<organization>/processos/<workflow_id>/registros/<ticket_id> renders the pinned record's authorized fields, sections and transitions through the common form engine. A mismatched process ID cannot open a record.
- /o/<organization>/processos/<workflow_id>/p/<page_key>/atendimentos/<visit_id> selects a resource visit for the reusable item/resource blocks.

One ProcessLive renderer reads interface.pages. It never selects a generated screen by an enrollment, incident or restaurant process key. Unknown blocks and invalid page keys are rejected; definitions cannot inject HTML, JavaScript, routes or arbitrary executable effects.

## Reusable primitives

The initial UI block vocabulary is: records, catalog, resources, items, batches, settlement and daily_summary. The editor exposes readable labels for these blocks, page names/keys, block order, workspace terminology, and symbolic roles for viewing, configuration and operation. The existing editor continues to configure form fields, section permissions, views and transitions. This is a bounded component vocabulary, not a universal application-code generator.

Records use the process's declared table/board projection and pinned field permissions. Catalog/resources/items/batches compose fast entry and destination routing. Settlement invokes the closing transition selected in interface.lifecycle; it is not tied to a restaurant key or a fixed business-stage name. Other transitions still use the ordinary workflow engine. Terminal transitions of an operational visit cannot bypass settlement. Operational commands and their data remain scoped by organization and workflow, with composite foreign keys and immutable captured lines/audit receipts.

The operations capability enables those reusable data primitives. A process can combine ordinary forms/stages with them. Form definitions do not need this capability. The interface configuration travels through clone/import/export; local role bindings and operational data do not. Published records stay pinned when an administrator changes the interface for new work.

The restaurant interface fragment in docs/examples/restaurant_interface.json illustrates three pages assembled from those blocks. It is a fragment for the normal workflow schema, not a standalone importable workflow. Its labels make resources appear as tables and the catalog as a menu. Another process can use rooms, counters or equipment and its own labels/data without a new screen implementation.

## Authoring flow

Open Modelos de fluxo, choose a blank starting structure or an example, and create a draft with an independent key. Under Interface gerada pelo processo, create pages, select their blocks, reorder blocks, choose the closing transition where applicable and map block access to declared symbolic roles. Configure names, fields, stages, policies and local bindings; review and publish separately. Page and block changes use the same revision/conflict checks as the rest of the definition.

The library includes school and restaurant example definitions. Copying a school example generates its staff-facing record/form/stage/view UI through the common engine. A restaurant example is ordinary configuration of the reusable operational blocks. There is no enrollment/incident/restaurant discriminator in the generated page contract.

## Migration and compatibility limits

The forward migration preserves saved menus, resources, visits, tickets, batches, captured prices/notes, audit receipts and day closures. It adds workflow ownership and process-consistent foreign keys. Menus created before their first visit get a normal process publication. Legacy operational publications receive a new version carrying interface metadata; original versions and pinned tickets are not rewritten. The populated old-schema test and the isolated preview row comparison cover preservation.

Phase-one specialized enrollment/guardian portals, confidential-case dashboards, and finance configuration endpoints remain as compatibility adapters. Existing guardian relationships, restricted projections, private documents, budget ledgers and academic evidence are preserved. Those adapters still contain domain-specific behavior; this change does not claim that all historical portal/guardian behavior can already be recreated using the seven current UI blocks. Their remaining capabilities need explicit reusable participant/projection/document/finance blocks before the entire original school demonstration satisfies the intended editor-only model.

The old /operacao URLs resolve existing saved visits into the common renderer. The legacy adapters are not automatically added to an unrelated organization's main navigation. Financial account setup remains a supporting configuration tool for declared finance processes, rather than a school-specific primary workflow.

Unsent item batches survive switching generated pages for the same visit in one LiveView session. Browser reload, navigation to another visit and server restart still require durable draft recovery work. Existing printer and real-customer activation limits remain unchanged.

## Local verification

Focused checks cover generated URLs and declared-block composition, ordinary reviewer access, independent operational processes, process-role access, clone/import/export, publication compatibility, database ownership constraints, old-schema data preservation and pinned versions. Existing school privacy/finance/concurrency tests remain regression gates. Browser checks confirm that agua mineral matches Água mineral locally, Enter selects and focuses quantity without adding an item, and adding/removing the selected item works. Seven saved operational preview tables matched their pre-migration row snapshots after excluding the added ownership field.

Final validation passed: mix precommit (183 tests, zero failures), Python runner/deployment checks (25 tests, zero failures), asset build and git diff whitespace checks. See docs/evidence/process-composition-local.json for the final working-tree evidence and check results. No deployment or real customer data processing is authorized by this local increment.

## Maintainability follow-up

The [modularity review](modularity-review.md) records the subsequent capability/interface contract extraction, component boundaries, reuse checks and remaining architecture prerequisites. Its evidence supersedes the source hashes above for files changed in that pass.

## Sprint 10 completion follow-up

The compatibility limits above describe the original composition checkpoint. Sprint 10
subsequently added generated participant correction/document/status/message pages,
configured authorized views and calendar projections, explicit finance resets/setup,
and reusable curated simulated delivery. The [recreation matrix](sprint10-generated-experiences.md)
records independent school copies and the equipment desk using common pages. Historical
adapters remain for pinned compatibility; Sprint 11 owns full populated replacement
and residual read-path/load acceptance.

## Session links across publications

An operational session's direct page link follows the definition pinned at its
opening, including old page names, labels and payment choices. Later publications
control new sessions and shared process setup. On an older session page, use the
current-process link for configuration or new work and the record-history link
for that ticket's pinned forms and transitions. Every link and command still
checks current grants; revocation removes an already open session page. Retired
versions remain read-only, including captured pre-capability batch history.
See the [Sprint 11 navigation evidence](sprint11-pinned-navigation-checkpoint.md).
