# UX01 inspection record — 2026-10-25

UX01 inspection and design-direction inventory is complete. This is an agent rehearsal, not independent user research or UX06 acceptance.

## Source and evidence boundary

Source HEAD: 8091b975fac29b6e19490d20f1958080af3ced0f. The workspace contains uncommitted redesign increments and pre-existing documentation. The original before-edit observations and index capture are retained in [first increment evidence](ui-redesign-first-increment.md). Today's captures show the current working tree, including authoring hierarchy, consolidated navigation and URL context; they must not be presented as historical before screenshots. A complete original screenshot matrix was not captured before implementation and cannot be reconstructed honestly.

## Surface coverage

| Surface | Observed behavior and evidence |
| --- | --- |
| Model index | Creation and existing work share the first section; import is secondary. [Current light wide capture](evidence/ui-redesign/ui-baseline-models-light-wide.png). Original dark wide index retained separately. |
| Simple draft | Title, editable status, section navigation and pending-form state inspected. Typed school-activity creation, date-field addition, role mapping, publication and new-version clone were rehearsed earlier. [Light wide capture](evidence/ui-redesign/ui-baseline-simple-draft-light-wide.png). |
| Complex participant draft | Enrollment draft 3 has review-based participant preview with explicit fictional-data disclaimer; page, role and stage controls are populated. [Light 1280 capture](evidence/ui-redesign/ui-baseline-participant-review-light-1280.png). Operational and finance controls still crowd page configuration. |
| Published editor | Published draft 1 states that cloning is required; save-item is disabled. [Light 1280 capture](evidence/ui-redesign/ui-baseline-published-light-1280.png). Earlier dark desktop/mobile captures remain in the increment record. |
| Process and board | User-approved consolidated navigation separates viewing from Iniciar registro. Gargalos is an actual configured board type. List, board, assignment and calendar controls use configured types, never label matching. Desktop, light/dark and mobile captures retained in the increment record. |
| Case detail | New isolated rehearsal record 33 showed revision, current stage, editable/read-only sections, next actions and history. Two-tab collaboration traced below. |
| Pinned flow | Current stage and version pin are explicit; accessible text lists full transition labels, destinations and terminal markers. Correction path Aprovação da área → Solicitada remains visible; graph order is not execution history. [Light 1280](evidence/ui-redesign/ui-baseline-flow-light-1280.png), [light mobile](evidence/ui-redesign/ui-baseline-flow-light-mobile.png). Earlier dark flow inspection is recorded in the initial baseline. |

Coverage includes 1280 × 720, 1440 × 900 and 390 × 844, both existing themes and long Portuguese labels. This is representative inspection across surfaces, not every surface in every size/theme combination. That broader final acceptance remains UX06.

## Collaboration journey traced

Two independent LiveView tabs used the same authenticated administrator account on newly created isolated demo record 33. No existing user ticket was edited and no business transition was submitted.

1. Session A entered a fictional requisition and supporting values.
2. Session B entered a different summary before A saved.
3. A saved. B showed a conflict and retained its local draft.
4. B opened Revisar alterações. The comparison showed A's saved values.
5. B explicitly selected Reaplicar minhas alterações. Its original whole-section draft was restored, including its blank values for fields it had not filled; this is not a field-wise merge.
6. B saved, and A received the changed summary. The history showed two form saves and creation.

[Conflict comparison evidence](evidence/ui-redesign/ui-collaboration-conflict.png). This establishes the basic same-section journey. Distinct-user permissions, independent-section saves, stale approval, lost acknowledgement, reconnect and revocation remain UX05/UX06 acceptance, not claims of this inspection.

## Confirmed defects and disposition

- P1: dark-theme conflict comparison uses very light text on a pale background and is difficult to read. Observed in screenshot; source uses a fixed pale background without a matching text override. Fix and verify under UX05.
- P2: mobile global navigation consumes most of the first viewport, delaying case/flow content. Keep navigation available, but reduce its footprint during layout work.
- P2: participant-preview checkbox renders disproportionately large. Verify input-type styling under UX02.
- P2: irrelevant operational/financial page controls remain visible in simple participant authoring. Finish contextual controls under UX02.
- P2: initial requisition key draft is labelled Solicitada even before Enviar para análise. Definition wording is misleading; recommend Rascunho in a future published version, without rewriting historical definitions.
- The original board → case → flow return-context loss is addressed by the current navigation increment. Browser round trip retained board, search 1 and version 1; a focused automated test covers a historical board's second card page.
- Existing good behavior to retain: explicit publication confirmation, per-form draft preservation, pinned versions, full textual graph labels, authorized bounded discovery and explicit conflict comparison/reapply.

## Layout direction

Use the existing visual tokens. Authoring order: title/save state → section navigation → identification and permissions → stages/form configuration → page composition → review/preview → explicit publication. The user explicitly approved the process arrangement: title → Lista / Quadro de Acompanhamento / Atribuições / Fluxo do Processo → records panel with Iniciar registro and filters. Keep distinct configured-page navigation when it actually offers multiple pages. Case direction remains identity/current stage and a compact next-action summary before detailed forms; no locking or guaranteed-approval claims.

UX01 closes the inspection inventory and records remaining defects. It does not mark the implementation groups complete or freeze a presentation candidate.
