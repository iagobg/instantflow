# D01: populated fictional school

The guarded setup now installs all four school scenarios. Fresh installs contain
29 cases: 12 enrollments, eight purchases, six trips and three incidents. This is
fixture data over the shared platform; no workflow engine or authorization bypass
was added. The setup safety rules are unchanged. Use [the guide](school-demo.md)
for commands, accounts and the PT-BR script.

Each new case and its initial history commit atomically behind a stable create
receipt and advisory lock. Reruns skip its population entirely, preserving edits,
documents, participant links and simulated delivery attempts. Targeted delivery
processing handles only the newly created case's simulated intent, never another
case's pending backlog. Fail-once provisioning and notification use authorized
retry before successful completion. Documents are harmless private synthetic PDFs,
uploaded by the family and reviewed by admissions, with the normal 30-day expiry.

The presenter has explicit admissions/IT grants alongside its prior non-confidential
grants. A separate admissions user creates enrollments so the financial confirmer
is not their requester. Director and assigned counselor accounts demonstrate the
confidential incident boundaries. Neither administrator status nor teacher grants
expose other people's incident fields. Counselor notes remain hidden from the
director; the reporter sees only the factual report.

## Publication and rerun evidence

The checked-in [inventory](evidence/demo-readiness/d01-school-inventory.json) comes
from the named instantflow_demo database. Two final setup runs succeeded without
reset and produced identical inventory objects. Purchase cases #2/#3 retain their
previous rehearsal transitions and #7 retains its edited draft state. Existing
passwords and the unpublished purchasing builder draft were preserved.

Browser inspection found the enrollment board had only a stage column. The demo
uses a supported publication with student name and school year configured. The
installer accepts only the exact original enrollment definition and unchanged
bindings as a known upgrade source. Existing v1 cases stay pinned; v2 receives
12 fresh primary fixtures. The local database consequently has 41 cases, including
12 historical enrollments. A fresh database starts with 29. The generic templates
and runtime were not changed.

## Browser inspection

The existing presenter session on port 4001 was used at its actual desktop viewport.
The purchasing board retained its rehearsed counts. Enrollment v2 showed 12 named
cards across seven stages; the version selector retained v1. Trips showed six named
cards across six stages, plus an empty cancellation column. The presenter incident
board showed zero cases despite three seeded incidents. No case was mutated in
this browser inspection. Screenshots:

- [Enrollment names and stages](evidence/demo-readiness/d01-enrollment-board.png)
- [Trip board](evidence/demo-readiness/d01-trips-board.png)
- [Presenter incident denial](evidence/demo-readiness/d01-admin-incidents-denied.png)

This is a fixture presentation check, not the full D04 rehearsal. Family/director/
counselor permissions and retry outcomes were verified in automated tests; their
complete browser walkthrough remains to be rehearsed. Independent UI-only builder
publication and local clock stability remain open D04 gates. Passing test runs do
not repair the earlier clock-related session rejection.

## Validation

The focused fixture/safety suite passed: six tests, zero failures (seed 243918).
Final instrumented mix precommit passed: 375 tests, zero failures (seed 865528),
184.4 seconds. Numeric diagnostics recorded 1186 token-age checks, zero invalid
results and largest future delta 0 ms. The preceding full run also passed 374
tests before the board publication regression was added. A final formatting check
initially found one call layout; formatting was corrected before the passing run.
The existing migration-redefinition warnings remain unchanged. No new dependencies
or assets were introduced. Git diff --check passed.

The final run's compact evidence is retained in
[d01-validation.txt](evidence/demo-readiness/d01-validation.txt).
