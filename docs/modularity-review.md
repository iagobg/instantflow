# Modularity and maintainability review

Reviewed 2026-10-21 against design/01-product.md, design/02-architecture.md, design/03-workflow-engine.md and design/06-school-templates.md. This review pauses feature expansion and separates verified builder behavior from remaining domain dependencies. It is a code/contract review with regression verification, not a claim that arbitrary business software can be generated.

## Finding

The correct foundation is organization → process identity → immutable published definition → declared pages and authorized projections → generic commands. Process identity chooses saved configuration; it must not choose a hard-coded school or restaurant implementation. Examples are portable starting definitions. Capabilities are bounded, reusable business primitives with authoritative server-side rules.

The current staff-facing builder follows that foundation. The complete school demonstration does not yet satisfy editor-only recreation: external relationships, some projections and document permissions still depend on school-specific adapters. Passing the historical school tests proves preservation, not removal of these dependencies. Treat their generalization as an architecture prerequisite before claiming the original end-to-end goal is complete.

## Changes made in this pass

- Introduced WorkflowCatalog.Capabilities as the closed additive capability contract. Previously, finance effect validation required the exact list [core, finance], silently preventing composition with operations despite the schema advertising that combination. Finance now checks membership; supported capability order is irrelevant. Missing core, duplicate and unknown capabilities remain invalid.
- Extracted WorkflowCatalog.Interface as a pure definition contract. Block identity, readable label and required capability come from one registry. Defaults, terminology, page and lifecycle validation perform no database reads.
- Kept Workspaces responsible for tenant-authorized publication discovery and process access. Its definition-only delegates preserve existing callers while the implementation lives in Interface.
- Moved phase-one route discovery into LegacyWorkspaces. Template-key compatibility checks no longer live in the main workspace discovery module. This does not remove the legacy endpoints or generalize their business behavior.
- Extracted reusable block templates into ProcessComponents and generated URL helpers into ProcessRoutes. ProcessLive retains navigation, session state, subscriptions, data loading and command orchestration. Templates do not own database queries or mutations. Removed fixed numeric section headings so block reordering has meaningful labels.
- Fixed a valid-definition crash when views is empty. Generated record pages now explain missing view configuration while retaining permitted record creation; resource-only pages do not require or load record projections.
- Corrected the operation-denied message to describe configured permission rather than imply that every command is administrator-only.
- Added contract checks between the shipped JSON schema and capability/block vocabularies. Added outcome tests for renamed resource lifecycles, pinned closure behavior across publication versions, and finance reservations composed with resource sessions, including denied premature closure and rollback.

No stored definitions, published versions, permissions or customer records are rewritten by this pass. No new database migration is needed. Existing process keys and routes remain compatible. Portable format 1.0 now accepts any ordering of the existing capability set; older readers with the previous enumerated-order schema will need an update to import a differently ordered list.

## Buildability matrix

| Goal | What the common builder supplies | Remaining dependency or constraint |
|---|---|---|
| New approval/service process | Organization-owned copies, fields, sections, roles, stages, guarded transitions, publication, generated record pages and URLs | Bounded field/action/view vocabulary; no arbitrary code or parallel branches |
| School enrollment, staff workflow | Staff forms, stage handoff, required values, history and access policies | Verified guardian/student relationships and curated parent portal still use Enrollment; copying JSON does not create those records |
| Confidential incident workflow | Restricted sections, named assignment, per-field projections, guarded closure | IncidentsLive dashboard still selects the incident example key; guardian communication projections remain specialized |
| Purchasing and field trips | Declared finance effects, shared-account protection, partial receipt guards, corrections and optional isolated calculations | Accounts/local bindings are configured separately; a generated finance-management block is not supplied |
| Restaurant service | Catalog, resources, visits, captured item prices, destination batches, handoff, settlement, daily summary | Item-service lifecycle requires a resource visit; inventory is consumption estimation; physical printer acceptance remains open |
| Another resource/item process | Same blocks with independent process key, terminology, stages, transition keys, data and role mappings | Settlement currently records BRL and cash/card/Pix; rental deposits, other currencies or refundable return semantics need explicit reusable capability work |

The finance/operations combination is now valid and tested, but selecting capabilities does not invent a sensible business graph. A configured closing transition must still be reachable, actor-authorized and satisfy required fields, finance and delivery guards. A rejected close rolls back the resource settlement in the same transaction.

## Remaining findings and required order

1. **Generalize participant relationships and external access before claiming complete school reuse.** WorkflowRuntime.Policy delegates guardian scope to Enrollment, excludes parent profiles from ordinary discovery, and the runtime retains explicit parent command restrictions. PrivateDocuments additionally recognizes application/document by name for guardian file access. Preserve these protections while introducing organization/process-scoped participant relationships, declared external projections and generic field-based document policies. Do not remove the checks to make renamed examples appear to work. Acceptance: clone and rename enrollment, establish new relationships through configuration, and exercise two unrelated external users without new routes/modules or cross-record access.
2. **Generalize remaining projections and supporting capabilities.** Replace incident-key dashboard selection with configured filters/projections; expose scoped finance setup/read models and curated communication as reusable supported surfaces. Acceptance: recreate enrollment, incidents, requisition and trip examples under independent keys with their complete authorized participant experiences. Existing privacy, audit, budget and concurrency tests remain mandatory.
3. **Remove operational assumptions only when their reusable contract is defined.** Session.waiter and existing command payloads retain the pilot-era name behind configurable actor labels. BRL, payment-method enum, São Paulo reporting defaults and product-unit consumption are fixed today. Do not advertise global locale/timezone/currency or general inventory semantics based on configurable labels alone. Introduce explicit contracts with compatible migration rather than rename database columns during this structural pass.
4. **Strengthen read-model scalability and UI completeness.** WorkflowRuntime.search currently loads authorized records and filters/pages in memory; Views.search adds per-record version/section reads. Generated record pages have a simpler table/board surface than the older calendar/dashboard screen. Move bounded pagination/filtering into authorized database queries and add supported view renderers before larger pilots. Keep pinned field permissions and tenant constraints intact.
5. **Continue splitting by responsibility when behavior changes.** TemplateLive still combines several editor panels, and the runtime/context modules coordinate substantial command logic. Extract cohesive panels and command implementations with shared tests as those areas evolve; do not create a dynamic plugin framework solely to reduce line counts. A closed capability registry remains appropriate for this modular monolith.
6. **Complete operational reliability separately.** Durable unsent drafts, real printer acceptance, account recovery/throttling, data lifecycle and production launch gates remain open. The modularity refactor does not satisfy those gates.

The directory_reference type is present in the portable vocabulary but ordinary value validation currently rejects non-null values. Define its scoped directory contract and editor UX before advertising it as an available general-purpose reference field. Calculations remain separately reviewed, isolated and disabled until their host gates pass; they are not an escape hatch for missing workflow primitives.

## Extension rules

1. Start with a new independent definition: roles, bindings, fields, stages, transitions, views, pages and labels. Publish it through the ordinary editor/import path.
2. If existing primitives are enough, change definition data only. Do not branch a generic route, LiveView or policy on an organization slug, process key or business-stage name.
3. If a primitive is missing, define its bounded schema, server-side commands, ownership, access and audit semantics. Add a reusable block only for its authorized read/interaction surface. Keep external effects outside database locks and behind the durable outbox.
4. Register the capability/block in the central contract and portable schema. Add behavior coverage for two independently named processes, denied cross-process/tenant access, idempotency, relevant concurrent mutations and pinned versions. Contract tests must keep editor/import/runtime vocabularies aligned.
5. Keep example initialization under explicit installation/seeding; runtime page loads never install a school or restaurant process. Local role/account/directory bindings and saved operational data never become portable template contents.
6. Preserve published versions, historical receipts and data ownership. Use forward migrations for any future stored-model changes and test populated preservation.

The next architecture increment should address participant relationships and external projections before resuming feature expansion that depends on them. Existing first-customer sprint status remains unchanged; this review does not mark those gates complete.

## Verification

Final verification: mix precommit passed with 190 tests and zero failures; asset build and git diff whitespace checks passed. The existing synthetic preview was restored and responds on port 4005. See docs/evidence/modularity-local.json for this pass's final checks and source hashes. Earlier process-composition and restaurant evidence describes earlier working trees.

## Planned remediation — 2026-10-21

Follow-up review of the sprint plans found that ownership/execution contracts and integration evidence were too concentrated in Sprint 11. The [builder architecture contract](builder-architecture-contract.md) now defines the early S09-T05 foundation, explicit correction/reset semantics, pinned/live binding lifetime, bounded query sequencing and incremental recreation matrix. It includes code-level findings from the current working tree. This is a planning correction; neither the historical checks above nor the revised sprint text constitutes implementation of the remaining architecture work.

The user requested these findings become higher-priority implementation sprints. [Sprint 09](../sprint_plan/sprint_09.md) owns reusable participant/reference/document policies; [Sprint 10](../sprint_plan/sprint_10.md) owns generated external experiences, configured views and finance/communication surfaces; [Sprint 11](../sprint_plan/sprint_11.md) owns operational contracts, scalable reads, cohesive extraction and the complete recreation/preservation gate. Pilot work moves to Sprints 12–15; the [roadmap](../sprint_plan/first_customer_roadmap.md#scope-tracking) maps earlier task IDs and keeps launch gates open. This planning follow-up does not change the historical verification result above.
