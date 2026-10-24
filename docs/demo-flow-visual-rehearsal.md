# D02 visual rehearsal — 2026-10-23

Rehearsed against the isolated instantflow_demo database at localhost:4001,
starting from ade7fba. The in-app browser's actual viewport was **1280 × 720**,
in the existing dark theme. All sign-ins, edits, transitions and draft operations
used the normal interface. No database edits, permission changes, password changes,
publication changes or external integrations were needed.

The earlier browser approval-service limit did not recur. The local server had
stopped and was restarted with the checked-in demo configuration. The presenter
session and its purchasing workspace/case flow were left open for inspection.

## Observed outcomes

| Check | Observed result | Evidence |
|---|---|---|
| Presenter login and populated workspace | Eight authorized cases with meaningful descriptions and stage labels | [Workspace](evidence/demo-readiness/d02-presenter-workspace.png) |
| Workspace → published flow | Version 1 and latest-publication context, diagram, seven-stage readable alternative, and navigation back to cases/builder | [Published flow](evidence/demo-readiness/d02-published-flow.png) |
| Diagram selection and keyboard | Compra selection focuses its connections; Tab reaches the scroll region with a visible outline; End scrolls from 603 to the maximum 1206 px | [Keyboard end](evidence/demo-readiness/d02-keyboard-end.png) |
| Allowed action | Presenter advanced case #3, Tintas para o ateliê de artes, from Aprovação financeira to Compra through Reservar orçamento; revision 4 → 5, one new history entry | [Transition](evidence/demo-readiness/d02-case-transition.png) |
| Connected flow refresh | Another already-open tab changed its current-stage marker from finance to purchase without a manual reload; version remained 1 | [Pinned flow](evidence/demo-readiness/d02-live-case-flow.png) |
| Current-stage entry position | After the fix below and a fresh navigation/reload, purchase is fully inside the diagram's scroll region at scrollTop 603 | [Centered stage](evidence/demo-readiness/d02-current-stage-centered.png) |
| Correction history and allowed edit | Case #7 retained its return-to-draft history and reason; presenter edited/saved its justification; reload retained the value | [Correction history](evidence/demo-readiness/d02-correction-history.png) |
| Restricted staff discovery | docente@escola.example saw one case, Cadernos; its own case offered submission/cancellation, without approval/reservation actions | [Restricted workspace](evidence/demo-readiness/d02-restricted-workspace.png) |
| Restricted staff flow | Its own pinned flow was readable without an authoring link; opening case #3's known flow URL displayed only the generic unavailable state | [Own flow](evidence/demo-readiness/d02-restricted-own-flow.png), [Denied case](evidence/demo-readiness/d02-restricted-case-denied.png) |
| Empty results | A nonexistent query displayed zero records; clearing it restored eight | [Empty search](evidence/demo-readiness/d02-empty-search.png) |
| Long label and editor reuse | A cloned, unpublished draft accepted an 86-character initial-stage label; the shared graph abbreviated it and retained its complete title; the editor item showed the full label | [Editor item](evidence/demo-readiness/d02-long-label-draft.png), [Editor graph](evidence/demo-readiness/d02-long-label-graph.png) |
| Published/draft separation | After that draft edit, the case flow still showed version 1 and the original Solicitada stage label | [Measurements](evidence/demo-readiness/d02-rehearsal.json) |
| Current board limitation | Gargalos por etapa still renders a card grid, without genuine stage columns; this remains D03 work | [Current grid](evidence/demo-readiness/d02-current-card-grid.png) |

The published/case flow had no document-level horizontal overflow. The readable
alternative includes complete transition names, destinations and initial/final/current
stage indicators. The graph itself remains independently scrollable.

## Finding and fix

A later-stage case initially selected and marked its current stage but opened the
diagram at scrollTop 0, leaving that stage below the visible part of the diagram.
The WorkflowGraph hook now centers the current-stage node on mount without an
initial animation. Manual stage selection retains its existing smooth pan and
respects reduced-motion preferences. The editor, which has no current case stage,
retains its original initial positioning.

The fixed behavior was verified by a fresh reload and fresh navigation, inspecting
both the rendered stage and its position inside the diagram's visible region.
No browser DOM mutation or injected UI action was used to obtain the result.

## Local state after rehearsal

- Case #3 is now Compra, revision 5. A fictional R$ 47,50 reservation was created
  through the normal command. No order, provider call or real payment occurred.
- Case #7 remains Solicitada, revision 5. Its justification now ends with
  “Revisão visual: conferir cores e medidas dos tecidos.”
- Draft #1 was cloned from requisition version 1 and saved with the long label
  “Solicitada — conferência detalhada dos materiais para oficinas pedagógicas de novembro”.
  It remains unpublished. The published definition and all case pins are unchanged.
- There are still eight cases: two draft, one academic, zero finance, two purchase,
  one receiving, one complete and one cancelled. The setup's original inventory
  describes a fresh fixture; rerunning setup intentionally preserves these edits.
- The active browser identity was restored to admin@escola.example. Both the
  purchasing workspace and case #3 flow remain available.

## Scope and limitations

This is a visual rehearsal of the purchasing fixture and D02 flow implementation,
not acceptance of the entire demo milestone. The two live tabs used the same
presenter identity; simultaneous updates from different identities remain covered
by backend/LiveView tests, not this browser run. The confidential incident,
enrollment and trip datasets are not installed by this checkpoint.

Older published case pins versus a newer publication, archived versions and
revocation remain automated-test evidence. The browser checked an unpublished
draft against the current case pin, rather than publishing a newer fixture version.
A complete independent-process build/publish/advance walkthrough remains D04.

Login, account switching and the exercised reloads succeeded. The previously
documented intermittent invalid-session observation was not reproduced here;
this run does not establish a fix for it. Other viewport sizes, light theme,
very large graphs and a screen reader were not exercised.

## Verification after the fix

mix assets.build passed. mix precommit passed with **360 tests, zero failures**
(seed 949960; 164.0 seconds). git diff --check passed. The hook's initial pan and
retained keyboard/manual selection behavior were verified in the real browser;
the full suite retains the existing flow authorization and version regressions.
