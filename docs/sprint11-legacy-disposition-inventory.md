# Sprint 09–10 compatibility inventory for Sprint 11

## Executed disposition — 2026-10-22

The owner explicitly confirmed in this chat: **“Yes—synthetic/demo only; retire
obsolete APIs and preserve historical data.”** This classifies deployed as well
as local consumers; it is an owner attestation, not a claim that a repository scan
or a remote database query established deployment usage. The owner also approved
the prepared shared-policy and remaining identity/route retirement patches after
automatic approval review rejected their security blast radius. No environment
is classified Unknown on the basis of absent local callers.

| Dependency | Consumer and retained-record evidence | Disposition / required behavior | Owner / removal milestone |
|---|---|---|---|
| LegacyAccess inference and guardian scope | Owner's synthetic-only attestation; former callers in Policy, PolicyQuery, Assignments, WorkflowRuntime and enrollment fixtures | Removed module and caller branches. New schema rejects guardian scopes. Explicit staff grants work in core-only definitions; undeclared relationships never authorize access. Historical JSON and mapped provenance remain immutable/read-only. | T03/T04; executable path removed in this checkpoint |
| Undeclared document fallback | Synthetic enrollment/incident examples and tests; populated rehearsal retains two original private objects across two organizations | Removed LegacyPolicy and Enrollment dependency. New attachments require declared policies. Supported lifecycle, independent review, quarantine, selected-field direct downloads and revocation tests replace the fallback. Files belonging to archived versions are excluded from automatic expiry purge; retained objects with no supported policy require operator backup/export access. | T03/T04/T05; fallback removed, historical storage retained |
| Guardian dual writes and invitation bridge | Owner attestation; historical rehearsal retains four mapped relationships (verified, pending and revoked), original source links and audit | Removed Enrollment mutation API and identity enrollment-link writer. Old invitation acceptance fails before creating users/memberships/relationships. Generated forward migration drops synchronization trigger/function and revokes runtime writes to enrollments/guardian_links. Generic explicit participant verification/revocation replaces ongoing synchronization. | T04/T05; writer and trigger removed, provenance frozen |
| Inferred resets | Historical-only behavior; explicit purchasing/field-trip corrections already declare targets | Removed LegacyResets. Missing reset is a no-op; new financial corrections still require explicit targets. Historical versions depending on inference are operator-classified as retired, never silently rewritten. Explicit reset/rollback and unrelated-section preservation coverage remains. | T03/T04; inference removed |
| Domain URLs and workspace dispatch | Owner attestation; former synthetic school/restaurant walkthroughs and UI tests | Removed enrollment/incident/budget LiveViews, domain contexts, LegacyWorkspaces and authentication dispatch. `/matriculas`, `/ocorrencias`, `/orcamentos`, `/operacao` and their old detail aliases return 404. Generic `/solicitacoes` is retained as a supported cross-process record surface, not a school adapter. Tests now exercise configured process pages and generic record routes. | T04/T05; routes/modules removed and 404 regression maintained |
| Unbounded list API | Test callers only in repository, plus owner confirmation of no external clients | Removed WorkflowRuntime.list/1 and its second selection engine. Existing denial, grant, participant and RLS assertions now use bounded WorkflowRuntime.search/2. | T02/T04; API removed |
| Waiter payload / no-argument dates | Synthetic operational fixtures and UI tests; historical column names in captured sessions/batches | Removed waiter payload acceptance and Operations.today/0; generated forms/fixtures use responsible_actor and organization-scoped today/1. Physical waiter columns remain unchanged; Operations.actor_name/1 reads their captured value. | T01/T04; API adapters removed, no column rename required |
| Missing operational declaration / closing inference | Synthetic historical versions and fixture construction | New operational publication requires interface.operations v1 and an explicit lifecycle closing transition. Runtime commands reject missing contracts. Archived historical definitions remain unchanged. Editor defaults initialize a new explicit declaration rather than invoking runtime fallback. | T01/T03; runtime fallback removed, new-definition guard maintained |

All six prioritized dispositions and the operational addenda are implemented.
Their complete validation, replacement-test map and migration/recovery limits are
recorded in the [retirement checkpoint](sprint11-retirement-checkpoint.md).
This closes the compatibility inventory, not all of T02/T03/T04/T05: the scale,
remaining contract/surface matrices and full builder acceptance gates remain open.

No user data or applied migration history was deleted. The forward migration is
tested on synthetic databases; this work does not claim a deployed migration.

## Original source inventory

Source inspection: 2026-10-22, during the first Sprint 11 operational increment.
This is the concrete starting inventory for D-32, not evidence about deployed
customers or permission to delete data. The entries identify repository behavior;
deployment consumers and retained-record requirements still need classification.

## Prioritized work

| Item and observed implementation | Required Sprint 11 action | Owner / completion evidence |
|---|---|---|
| **1. Definition-based legacy access.** `WorkflowRuntime.LegacyAccess.legacy_definition?/1` infers legacy status from absence of participants, finance interface, communications and reset declarations. `Policy` and `PolicyQuery` use it to select parent/guardian behavior. | Remove the inference if legacy execution has no evidenced consumers. If compatibility is needed, scope it to evidenced historical versions using trusted provenance outside user-authored optional fields. A newly published minimal/core definition must not become legacy simply because optional capabilities are absent. | T03/T04: new core-only definitions, explicit parent staff grants and supported query/detail parity remain correct; each retained historical exception has a classified consumer. |
| **2. Undeclared document-policy fallback.** `PrivateDocuments.Policy` delegates fields without `document_policy` to `PrivateDocuments.LegacyPolicy`, which depends on Enrollment and the literal application/document field names. | Require explicit supported document policy for new attachments, or reject unsupported authoring/publication combinations. Retain fallback only for the historical set justified by D-32; retire it when that set has no active need. Preserve generic file storage and the Sprint 10 direct-download projection fix. | T03/T04: editor/import/publication tests cannot introduce fallback; ordinary document reads/review/download do not call Enrollment; any retained historical access is separately tested. |
| **3. Guardian dual-write bridge.** Migration `20261021231607_backfill_guardian_participant_relationships.exs` creates `sync_guardian_participant()` and the `synchronize_participant` trigger. Participants and directory code distinguish `legacy_guardian_link_id`. | Inventory old invitation/verification/revocation writers and their consumers. Retire them together with the ongoing synchronization bridge when no longer needed. Decide whether mapped records remain read-only or require an explicit audited conversion before removing source-specific restrictions. | T03/T04/T05: retained identity links, verification provenance, revocation and tenant isolation survive migration/restore; retired writers cannot recreate legacy relationships. |
| **4. Inferred finance resets.** `WorkflowRuntime.Corrections` calls `LegacyResets` when a transition lacks `reset`; the adapter clears non-money sections on release back to the initial stage. New-publication validation already rejects that financial combination without explicit targets. | Preserve that validation; audit historical versions that actually exercise the effect. Remove the inferred effect if synthetic-only. If active versions need it, isolate its eligibility explicitly rather than treating every missing reset as a historical contract. An ordinary transition without reset should remain a no-op for invalidation. | T03/T04: explicit target/reset rollback tests stay intact; unrelated/confidential sections survive ordinary corrections; any retained inferred behavior is tested only against its classified historical version. |
| **5. Legacy workspace and domain-route discovery.** `WorkflowCatalog.LegacyWorkspaces` checks enrollment/incident template keys and old role rules; `UserAuth` calls it for compatibility routes. | Classify each route and its underlying service, then remove synthetic-only screens/auth hooks or retain narrow read-only/temporary routes for evidenced consumers. Removing navigation alone does not retire a reachable route. Do not delete reusable finance or document capabilities with their former screens. | T03/T04/T05: common school recreations need no template-key dispatch; direct requests to retired routes cannot mutate records; retained redirects/read-only routes reauthorize current access. |
| **6. Unbounded list compatibility API.** Repository search finds `WorkflowRuntime.list/1` calls in tests and no calls in lib. This is a source finding, not a deployment-client inventory. | Move tests to the shared bounded search/projection contract, preserving their authorization assertions, then remove the obsolete API if no external consumer is evidenced. Do not keep a second read engine to satisfy old tests. | T02/T04: caller inventory and equivalent privacy/paging tests; one maintained generic query boundary. |

## Publication and retirement sequence

1. Add actual consumer/record evidence, disposition (remove, read-only, migrate or
   temporary execution), owner and measurable removal condition to each retained
   entry. Unknown deployed usage must be resolved before the D-32 acceptance gate.
2. Close new-definition entry into retired semantics first. Inspect editor,
   import, clone and example-installation paths, not just runtime fallbacks.
   Ordinary fields omitted from a core-only definition are not a legacy marker;
   a user-supplied compatibility flag is not trusted historical provenance.
3. Replace synthetic fixtures and transfer business/security assertions to the
   supported builder. Then retire obsolete routes, adapters and database writers
   together, retaining only the evidence-backed historical subset.
4. Where database changes are needed, generate forward migrations through Mix.
   Do not edit applied migration history or erase audit/source identifiers merely
   to remove runtime code. Verify both fresh installation and populated upgrade/
   restoration, including explicit disposition of pending work.

## What should remain

- Version-pinned supported definitions, live authorization and explicit resets.
- Generic participant relationships, reference eligibility, document storage and
  selected-field/file release checks, curated snapshots and shared form conversion.
- Historical audit/data provenance where retention is required. The
  `Enrollment.Document` schema name or a historical column name alone does not
  justify a storage migration; behavioral coupling is the priority.

No runtime implementation or data was changed by this inventory. The first four
items are the strongest S09/S10-specific follow-up work; the last two are older
paths retained through those sprints. Existing Sprint 11 operational adapters
(waiter payloads, date defaults and missing operational contracts) remain separate
D-32 entries and must follow the same consumer-evidence rule.
