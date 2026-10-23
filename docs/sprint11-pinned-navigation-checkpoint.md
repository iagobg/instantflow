# Sprint 11 pinned operational navigation checkpoint

Executed 2026-10-23 on read-support checkpoint revision 7f0e5ad. Scope: T03's
supported pinned-session links after page and role/payment mapping changes.
T03's full contract/public-entry/form matrix is not closed by this increment.

## Reproduced gap and correction

A session opened on a supported publication became unreachable through its old
page URL when a later publication renamed that page and removed the operator's
role mapping. Operational commands still honored the original pin, but ProcessLive
resolved the page and workspace from the latest publication first. The maintained
regression reproduces the redirect before this change.

Session links now resolve the actual session/ticket/version with current tenant
and pinned-view authority. Operations.version_for_visit performs that minimal
resolution without loading batches, lines or a whole installed-process catalog.
Operations.visit shares its resolution, and Operations.workspace can accept a
session ID for a narrow historical projection. As corrected by the
[three-checkpoint review resolution](sprint11-three-checkpoints-review-resolution.md),
that projection includes the requested session and the item-entry catalog, with
no resource occupancy or process-wide report. Shared reads stay on the current
workspace and require its current permission. Explicit process
ownership is checked; a valid session ID cannot be attached to a different process.
These methods run inside the existing Tenant read gate and fresh grant lookup.

ProcessLive uses the pinned page keys, labels, process name, payment options and
session actions on direct links and reconciliation. Older-session pages retain
items, batches and settlement. Shared catalog/resource configuration, new-session,
report and finance-setup/summary blocks belong to the current process workspace;
they are not silently rendered with newer bindings in an old page. The page
explains that the session uses the rules published at opening and links to the
current process for new work and setup. That destination reauthorizes current
access. The existing record-history link keeps the original ticket's form,
transition and composed-effect rules.

Current publication still governs new openings. A staff operator with the old
pinned role can finish that session even if the latest publication maps only
administrators; it grants no access to new work or current setup. Removing the
operator's actual current grant redirects the open page and rejects forged
settlement, version-resolution and workspace reads. Failed attempts create no
operation receipts. Regranting authority restores the pinned supported session.

## Retained archival behavior

Retired session versions remain read-only. Actual archived session rows that
predate optional capability declarations retain captured actor/resource and batch
history through a read-only batches projection, including captured amounts. This
is a read projection of retained operational rows, not a missing-contract execution
default: publication and command guards are unchanged, and no item, handoff,
print, setup, opening or checkout control is enabled for archived work.

## Verification

pinned_operational_navigation_test.exs exercises supported clone/save/publish,
opening via a granted staff identity, page removal, role remapping and narrowing
new payment choices to cash. The old URL keeps Pix under its supported pin,
reconciliation preserves it, and current-process discovery remains denied to that
old-only role. Cross-process session IDs fail closed. Real access revocation
removes the live page and denies commands without receipts. After regrant, the
actual rendered checkout form settles with Pix; a new visit on the same resource
pins the latest version and exposes cash alone.

A second generated-page test covers a retained pre-capability archived session
with captured line amount and no operational write controls. Existing operations,
retired replay and archive UI regressions remain mandatory. Full validation and
source/log hashes are recorded in
[evidence](evidence/sprint11-pinned-navigation-checkpoint.json).

## Remaining gates

Sprint 11 remains In progress, 1/5. Complete T02 browser/full memory/supporting
volume work, the wider T03 field/surface/public-entry and mixed-version matrices,
T04 residual ownership cleanup and T05 full recreation. No fix for the previously
observed intermittent LiveView reload is established by a passing run. Physical
printing and real-customer acceptance remain later gates. No serving migration,
deployment or destructive reset was performed.

## Validation result — 2026-10-23

The full precommit alias passed 294 tests (seed 411553); asset build and whitespace
checks passed. The targeted navigation/archive/replay group passed 10 tests
(seed 89588). The old URL regression failed before the change (seed 220900).

The first full run (same seed 411553) had one invalid LiveView session-token
verification failure in the incident UI test. That file passed all three tests
on isolated same-seed recheck. The complete same-seed precommit alias then passed
with a temporary numeric-only token-age/clock probe; it recorded no age/clock
delta event. No token/session/signature arguments were traced or logged by that
probe, and no validation, assertion or retry behavior was changed. The failed
log is retained. Its cause and relationship to the earlier copied-trip reload
remain unestablished; this checkpoint does not claim to fix that observation.
