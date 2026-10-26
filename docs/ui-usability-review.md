# UI usability review and redesign direction

Date: 2026-10-24. Scope: model index/editor, process workspace, record board, published flow and case detail. This document combines the builder review with the requested process-examination review.

Evidence: current source templates and graph hook; user's observation that the board is hidden behind a view called “Gargalos”. The label was not located in the searched application/template source and may be authored configuration. Do not hard-code behavior based on that label. Live visual inspection was not completed: the preceding browser-access request timed out. Spacing, contrast, clipping and viewport findings require browser verification before implementation acceptance.

## Main conclusion

Make creating a process, following its cases and understanding its rules distinct, readily discoverable activities. Keep the existing domain-neutral architecture. Improve information order and contextual controls before adding functionality or replacing the visual system.

“Process examination” covers the process workspace and published-flow screen here. Case detail is included where the journey crosses into editing and approval.

## Confirmed findings and proposed changes

| Priority | Evidence / issue | Design direction |
|---|---|---|
| P1 | TemplateLive renders participant preview before the editor title; preview is unconditional | Put name/status first; move preview to review/testing; show useful empty guidance when no participant page exists |
| P1 | ProcessComponents places view selection inside a submitted filter form | Expose a direct “Quadro por etapas” action beside the other available record presentations; do not require selecting “Gargalos” and pressing Filtrar |
| P1 | Builder page/block composition precedes graph and basic configuration | Organize authoring around overview, form, stages/approvals, people/permissions, pages/views and review/publication |
| P1 | Case next-step actions follow numerous capability-specific sections | Bring a compact current-stage and next-action summary near the case heading; keep detailed forms below and preserve all dirty/stale/guard behavior |
| P2 | Builder generic item picker always displays section and transition parent selectors | Show only applicable parent controls; offer contextual “Adicionar campo”, “Adicionar etapa” and “Adicionar aprovação” entry points |
| P2 | Model creation and JSON import have equal prominence; drafts appear afterward | Primary create action, easily found existing work, secondary import disclosure |
| P2 | Graph nodes truncate labels over 25 characters, expose technical keys, and impose at least 840 px SVG width | Prefer readable labels, selected-stage details, controlled diagram scrolling and deliberate fit/centering behavior |
| P2 | Flow navigation/back links do not carry explicit board search/version/page context | Restore the authorized source view when returning; define URL state and safe fallbacks |
| P2 | Repeated explanatory and implementation text competes with work | Keep essential status visible; move detailed explanations into contextual help |
| P2 | Many button-like controls represent navigation, saving and editing | Establish distinct hierarchy for navigation, primary actions, secondary actions and destructive controls |

Priorities describe usability importance, not security defect severity.

## Builder proposal

Persistent heading: process name, draft/published status, saved/unsaved state, return to models and “Revisar e publicar”. Keep publication a reviewed, confirmed action.

Navigable sections, not a mandatory linear wizard:
1. Visão geral: name, description and configuration readiness.
2. Formulário: sections and fields.
3. Etapas e aprovações: stages, transitions and flow.
4. Pessoas e permissões: symbolic process roles, current local mappings and section access.
5. Páginas e visualizações: generated pages, configured list/board/calendar options and participant pages where relevant.
6. Revisar e publicar: actionable validation, role review, participant-page preview and publication.

Rename “Prévia sintética de participação” to “Prévia da página do participante”. Explain that it uses fictional data and executes no actions. Do not imply that previewing a symbolic role proves the actual grants or relationships of a real user. Keep draft revisions and published version numbers distinct.

Use plain labels: “Papel no processo”, “Identificador técnico”, “Nome exibido”, “Quem desempenha cada papel”. Advanced identifiers/version metadata/JSON stay available in secondary disclosures. No automatic changes to existing stable keys.

Condition operational and participant controls on configured capabilities and intent. Do not hide a configured validation error merely because its controls are collapsed. Show an error summary linking to the affected section.

## Process workspace and stage board

Proposed heading: process name, brief description, authorized “Novo caso” action, visible access to records and published flow. Respect declared page/block composition rather than inserting a universal school dashboard.

Within record access, distinguish:
- Presentation type: Lista / Quadro por etapas / Calendário, only when configured and authorized.
- Saved configuration: a named view such as “Gargalos” or “Todas as solicitações”.
- Filters: search, stage, assignment and configured fields.

“Gargalos” may be a useful analytical view name; it must not be the only clue that a stage board exists. Presentation switching should select an actual authorized configured view, not reinterpret a table definition as a board. With multiple boards, expose a bounded named-view chooser. A board beyond the current discovery page must remain discoverable without fetching all definitions. With no board, show author-only setup guidance; ordinary users should not receive a misleading disabled feature.

Use “Lista” for the existing record presentation unless it is actually rendered as a table. Do not label an existing card list “Tabela” merely for symmetry.

The board should prioritize:
- Stage name and authorized total.
- Useful configured case title and a small number of authorized details.
- Obvious card opening and keyboard focus.
- Clear zero-results/loading/denied states and reset-filter action.
- Per-column pagination and honest “shown / matching” counts.
- Visible publication context when historical versions are selected.

Preserve selected view, compatible filters, version and page when opening a case and returning. Define which filters reset when changing incompatible versions. Revalidate URL parameters and authorization; never trust saved navigation as access permission.

Do not add drag-and-drop in this sprint. Opening the case to execute an authorized transition remains the intended interaction.

## Published flow: improve orientation, not the execution model

This is a process graph, not necessarily a tree: return/correction paths and branches are valid. It is also not a record's execution history. Do not mark stages completed simply because they precede the current stage visually.

Keep:
- Process name and publication identity.
- Clear distinction between latest published overview and a case's pinned version.
- Current-stage marker for case context.
- Authorized paths only, readable connections list and reduced-motion support.

Improve:
- Put the diagram closer to the heading; reduce introductory text to one useful sentence.
- Separate “Etapa atual” from the stage selected for inspection.
- Provide “Etapa atual” in case context and “Visão geral” / reset controls.
- Show full selected-stage labels and visible outgoing connections in an adjacent/below detail area.
- Support node selection by keyboard as well as pointer if node interaction is added; retain the dropdown as an accessible alternative.
- Wrap labels where practical; move stable technical keys to secondary details.
- Use line style, arrow direction and text as well as color for forward/return paths.
- Preserve the reader's position during live refresh unless they explicitly recenter.

Fit-to-view and zoom are stretch work: fitting a large graph must not make labels unreadable or trap scrolling. Keep the current shared graph component and layout; no new graph engine or drag-only editor before the freeze.

The selected-stage detail is descriptive. A visible edge does not mean the current user can execute it. Direct users to the existing case actions, where current authorization and guards are evaluated. Never expose hidden guards, bindings, fields or private transitions through a new tooltip.

## Case detail and shared application polish

Provide a compact header with case identity, current stage, applicable version and return context. Near it, show available next actions or an understandable reason for needing review/saving. Sections should show their own saved/unsaved/pending/conflict state.

Preserve explicit saves and conflict comparison/reapply. A new sticky action region must not submit a different form, discard drafts, create a new command key on retry or bypass stale-review checks. Distinguish connection status from editing presence; presence is advisory.

Keep history and optional capabilities accessible without allowing them to obscure routine editing. Details may collapse, but required errors and actionable failures must remain discoverable.

Apply shared spacing/type/action tokens and navigation conventions across touched pages. Audit existing light/dark themes, keyboard focus, long Portuguese labels and narrow screens. This is not a full rebrand.

## Review scenarios

- New administrator creates “Solicitação de atividade escolar” without JSON.
- Staff opens the process board directly, searches, opens a later-page card, then returns to the same context.
- Two authorized sessions edit the same section, compare a conflict, and explicitly resolve it.
- Two reviewers attempt competing transitions; only a valid command takes effect.
- Restricted staff and family accounts see only their configured surfaces and fields.
- Historical case flow uses its pinned version even after a newer publication.
- A non-school workflow uses the same UI without school-specific labels or branches.

Record task completion, wrong turns, assistance and errors for any usability participants. Report who participated and the sample size; an internal rehearsal is not independent usability validation.

Implementation and acceptance are tracked in [UI redesign sprint](../sprint_plan/ui_redesign.md).
