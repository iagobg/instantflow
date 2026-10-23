# Sprint 11 bounded operational read checkpoint

Executed 2026-10-23 after participant-release revision 822302e. Scope: remaining
operational collection/report reads in T02 and the associated T04 read ownership.
Full T02 scale/browser/discovery acceptance remains open at this checkpoint.

## Projection and interaction changes

Operations retains fresh tenant admission, current/pinned view permission, command
locks and business guards. Its ReadModel owns operational query projections. The
workspace now returns 25 catalog products and 25 resources with exact count/page
metadata and stable category/name/ID or name/ID ordering. Open-session occupancy
is fetched only for the selected resource page, at most 25 rows. Supported session
history returns ten destination batches per page, each with at most the 100 lines
accepted by the maintained batch command. Captured prices, names and notes remain
unchanged. Session totals and settlement guards aggregate the complete session.

Generated screens expose catalog/resource search and pagination, batch pagination
and estimated-consumption pagination. Whole-catalog search handles PT-BR accents
and case, including uppercase accented names under the isolated database locale.
Local picker matching and keyboard selection still operate on the displayed
catalog page. Its separate whole-catalog search reaches later results; no item is
silently inaccessible behind a hard limit. Changing search/pages preserves the
in-flight cart for the same session. Printing uses the currently selected batch
page. All mutations still reauthorize through Operations.

The LiveView passes its declared page blocks to the workspace projection. Pages
without catalog/items, resources or daily summary do not load those collections
or report. Historical-session projections continue to omit unrelated occupancy
and reports regardless of broader current grants. They can page only their own
batches and deliberately needed item catalog.

## Full-day SQL aggregates and retained snapshots

Daily counts/paid totals group in SQL by the bounded status/payment vocabulary.
Line amounts group by session/batch state, so open, archived, paid and cancelled
amounts remain distinct without one total query per open session. Consumption
aggregates all eligible lines by product, then returns 25 aggregate rows per page
with exact counts. Latest captured names use explicit line-ID ordering. Cancelled
orders and cancellation notices do not inflate sales or estimated units.

An allowed price of 100,000,000 centavos times 999 units exceeds PostgreSQL int4.
Amount expressions now multiply using bigint before summing; the maintained test
checks 99,900,000,000 through session total, open report, settlement and Pix total.
No currency/payment semantics or permitted input bounds changed.

Day closure is a command snapshot exception, not an unbounded interactive report:
it still stores the complete aggregated consumption list in the immutable summary.
The ordinary report projects closed totals without fetching that potentially large
stored consumption array. The historical data stays in storage. A 30-product
closing regression verifies all 30 stored groups while report pages contain 25 and
five. No existing rows or captured summaries are rewritten.

## Evidence

The pre-change quantitative read regression failed with 62 fetched rows where the
page contract allows 25 (seed 803165). The maintained post-change test opens 60
sessions and creates 62 products/61 resources. It asserts at most 25 rows in any
workspace query and fewer than 35 queries, exact whole-day open/cancellation/unit
amounts, stable nonoverlapping pages, clamped page inputs and filtered occupancy.
The fixture uses supported commands; low-level telemetry observes query results.

The generated-page test reaches a later resource, searches an accented later
product, preserves it across another search, submits the cart, adds 11 more batches
and prints from page two while the complete total remains R$ 284,50. Existing
current operations, pinned navigation, archive, replay and settlement tests remain
mandatory. The focused group passes 16 tests (seed 972804).

Full validation, retained failure diagnostics and hashes are recorded in
[evidence](evidence/sprint11-operational-read-checkpoint.json). The initial full
run hit the previously observed same-URL LiveView redirect in OrganizationLiveTest;
its failure is retained and investigated without relaxing assertions or token
checks. This report does not attribute that failure to a cause without evidence.

The isolated organization file passes 3 tests at the same seed 290848. The full
same-seed precommit then passes 331 tests under the numeric-only clock probe; no
invalid-age/clock event was recorded. Asset build and whitespace checks pass. No
assertions, token checks or retries were changed; the intermittent cause remains
unestablished.

The remaining T02 supporting workload, browser/full VM memory and discovery paths,
T03 remaining capability/binding matrix, residual T04 editor responsibilities and
T05 complete recreation/recovery are still open. Sprint progress remains 1/5.
No serving migration, deployment or destructive reset was performed.
