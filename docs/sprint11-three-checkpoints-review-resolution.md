# Sprint 11 three-checkpoint review resolution

Executed 2026-10-23 on b6b636223e893d3762b6ec8bc299035010dc5987.
Scope: the P2 authorization/projection finding in
[sprint11-three-checkpoints-review.md](sprint11-three-checkpoints-review.md).

## Correction

The maintained pinned-navigation regression reproduced the review finding:
workspace admission through an old session returned both that session and a newer,
admin-only session, even though current workspace and direct newer-session reads
were denied. The pre-fix run failed that assertion (2 tests, 1 failure, seed 239865).

Operations.workspace now resolves the requested session through the same fresh
pinned-view authorization and process-ownership gate as Operations.visit. When
its version differs from the current publication, it returns only that session
and the catalog needed for item entry. Resource/occupancy rows are empty and the
daily report is absent (nil); their queries are not executed. This applies even
to administrators visiting an old session. They must enter the current workspace
to obtain shared projections under current admission. Retired session pages also
use the narrow projection even when their version is the latest publication.

The session's captured metadata, authorized batches and lines still come from
Operations.visit. ProcessLive accepts the absent report and resets the consumption
stream to empty; resources and opening choices remain empty. It continues to use
pinned pages, labels, payment choices and actions. Current-version operational
pages retain their shared workspace behavior after current authorization.

## Regression coverage

The maintained navigation test now opens a distinct current-only resource/session
before loading the older session. It checks denial of direct newer access, only
the requested session in historical projections, no resources or report for staff
or admin historical reads, and separately authorized current workspace occupancy
and report counts. It then uses rendered forms to add a catalog item, submit and
handoff its batch, revoke the real grant, verify redirect and forged-settlement
denial without new receipts, regrant access and settle R$ 25,50 with pinned Pix.
The latest session still exposes only its new cash payment choice.

Cross-process IDs, cross-tenant reads, archived captured history, current menu and
resource flows, receipt replay and current revocation remain covered by the focused
group and full suite. The focused group passes 17 tests (seed 524033). The full precommit alias passes
294 tests (seed 984831); the asset build and whitespace check pass. The original
independent review probe now passes its one test (seed 831618). Check results
and file/log hashes are recorded in
[evidence](evidence/sprint11-three-checkpoints-review-resolution.json).

Sprint 11 remains In progress, 1/5. This resolves the reported projection finding;
full T02 supporting-volume/browser/BEAM measurements, the remaining T03 matrix,
T04 ownership cleanup and T05 recreation remain open. Previously observed
intermittent LiveView token/reload behavior remains unexplained. No serving
migration, deployment or destructive reset was performed.
