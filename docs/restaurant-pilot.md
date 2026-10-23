# Restaurant pilot: operational workspace

Status: implemented locally with synthetic fixtures; customer activation is still gated by Sprints 12–14. Date: 2026-10-21.

## Confirmed discovery inputs

The owner needs table orders, kitchen handoff, checkout verification and table reuse between groups. He alone will operate a Windows notebook; waiters do not need accounts. A USB POS-80 thermal printer is available. Products may go to different destinations (for example soup to Cozinha and asado to Parrilla), requiring separate papers. Every paper needs the table, waiter, time and ordered items. Menu setup must precede routine service so names and prices are selected rather than retyped. Checkout and daily totals are required. Inventory impact can initially be demonstrated.

This is user-reported discovery, not direct operator observation or customer sign-off. Customer identity, operating volumes, baseline entry times/errors, review date, support/commercial terms and success targets remain open under S12-T01.

## Architecture

The main workspace now follows the [organization/process/generated-page model](process-composition.md). That document supersedes the initial presentation/installation description below.

`Instantflow.Operations` provides tenant-owned catalog products, named resources, resource sessions, structured immutable line snapshots, destination batches, audited idempotent commands and daily closure snapshots. Restaurant terms are the first operational presentation of these primitives. It does not add restaurant field types or arbitrary executable actions to the workflow interchange format.

Each visit creates a normal version-pinned `resource_service` workflow ticket through `WorkflowRuntime.command/2`. Closing the visit transitions that ticket in the same transaction. Generic transition events cannot bypass operational checkout. Runtime history records opening/closing; append-only operation receipts attribute catalog changes, batch creation, cancellation, print requests and handoffs to an actor. The operational page is the authoritative view for item details and totals; generic workflow JSON export does not export these records. This is an explicit bounded context, not a universal configurable operational-view builder.

Processes are created, reviewed and published in the normal editor. Interface pages and reusable blocks are declared in the versioned definition. Block access uses symbolic process roles; settlement additionally respects the pinned workflow transition policy. The example binds its operator role to the local administrator.

Tenant transactions revalidate membership and user activity, apply non-owner RLS and use composite ownership foreign keys. A tenant-specific advisory gate serializes operational writes after the authorization gate. This deliberately favors correctness at the first single-operator scale; load acceptance and resource quotas remain Sprint 12/11 work. Immutable lines, receipts and daily closures cannot be updated or deleted by the runtime. Catalog revision checks prevent silently charging a changed menu price after it was selected. All money uses integer cents.

## Walkthrough

1. Sign in as a local administrator and open **Processos** and select the published process. Expand **Preparar cardápio e mesas**. Add products with category, price in reais and destination; add named tables. Edit or deactivate products without deleting their history. Destination spelling groups tickets, so use consistent names.
2. Select a free table, enter the responsible waiter and choose the business date. This starts a new visit; it never overwrites the previous group.
3. Search the local accent-insensitive dropdown and press Enter to select its first match, then set quantity/preparation notes. Optional one-click shortcuts remain available. Review the unsent batch and its total. Unsent items live only in this LiveView: register them before leaving/reloading. Durable draft recovery remains Sprint 13 work.
4. Confirm the waiter for this batch and choose **Registrar e separar por destino**. Names, prices, destinations, quantities and notes are captured. Each destination gets its own ticket. Additional orders become additional tickets.
5. Print each ticket and manually hand it to its destination. Print requests do not mark handoff. A second print request is labeled **REIMPRESSÃO**; cancelling the OS dialog still consumes a print-request number. Confirm manual delivery separately.
6. To correct a submitted batch, cancel the whole destination ticket with a reason, deliver the cancellation notice, then enter replacement items. Original lines remain. Partial line cancellation, refunds and after-settlement corrections are not supported; confirm this operating limitation with the owner before launch. Cancelled orders are excluded from bill totals. No cancellation implies ingredients returned to stock.
7. After verifying the bill and receiving payment, record one method (Dinheiro, Cartão or Pix) and settle. Any pending order/cancellation handoff blocks settlement; a changed total requires review. The table becomes available, while its old visit remains addressable by its URL. Payments are manual records, with no bank integration or fiscal document. Discounts, service charges, split/partial payments and transfers between tables are not delivered.
8. Consult the business date for settled sales, manually recorded payments, open balances, cancelled-order value and estimated product-unit consumption. Sales/payments are attributed to the visit's selected business date even when settlement occurs after midnight. Close a day only after all visits on that date or earlier are settled. Closure captures an immutable summary and blocks new operational writes for that date and earlier. There is no automatic cutoff or reopening; agree the date policy and correction procedure before live use.

## Printing acceptance still required

Target: Windows + USB POS-80. Browser/Windows driver printing with a 72 mm content area is implemented for nominal 80 mm rolls. Choose the correct roll width in the installed driver, disable browser headers/footers and verify margins/scaling. No raw USB, ESC/POS, automatic cutter, silent printing or spooler acknowledgement is implemented. All destinations can use the same printer for manual distribution.

On the actual notebook/printer, verify accents, long product names, multi-line notes, long tickets/page breaks, two destination tickets, legible table/waiter/time, cancellation notices, reprint labels, cancelled dialogs, disconnection and paper-out recovery. Never infer physical printing from a command receipt. Physical device acceptance remains unverified.

## Verification and remaining launch gates

Focused context/LiveView checks cover setup/edit/deactivation, captured prices and stale catalog revisions, destination splitting, repeated commands, totals, cancellation notices, handoff-gated settlement, immutable daily summaries, table reuse, authorization and tenant scoping. The existing independent runtime-role harness additionally exercises simultaneous opens, duplicate batch commands and absent/wrong tenant context using a real non-owner pool. Reconnect/heartbeat events refresh the workspace; administrator revocation redirects it through the shared authentication lifecycle.

Inventory currently reports estimated ordered product units excluding cancellations, including open visits. There are no recipe/ingredient deductions, stock balances, receiving, waste adjustments or actual inventory movements.

This implementation does not complete S12-T01 or the S12 demo-isolation/access controls, resumable organization onboarding, durable draft recovery, operational backup/monitoring/export/offboarding or customer/printer acceptance. It does not authorize real customer data or deployment. Existing school demonstrations and Python acceptance retain their original limits.

## Outage inspection

Before implementation resumed, Git status matched the earlier inspected dirty tree. Git diff whitespace checks and full object integrity checks found no corruption, only unreferenced objects. All 277 inspected source/document files decoded as UTF-8 and contained no NUL bytes. The existing assets/tsconfig.json contains comments, so strict JSON parsing is intentionally inapplicable there. No project source files were unexpectedly empty. No agent edits had occurred before the outage.

The ignored local PostgreSQL log contained interrupted-write NUL bytes and was preserved. The existing local cluster recovered through WAL replay and reported ready on port 55432. Subsequent migrations and tests succeeded. This is a scoped source/recovery check, not a claim that every filesystem sector or historical database row was exhaustively verified.

## Local acceptance evidence — 2026-10-21

- Final mix precommit: 170 tests, 0 failures; warnings/format/unused-dependency checks passed.
- Python runner: 17 tests passed. Deployment: 8 tests passed. Final asset build passed.
- Focused operational + existing runtime-role suite: 32 tests passed before the final full run.
- IAB browser, isolated synthetic database: Windows-accessible localhost preview, menu selection, Cozinha/Parrilla ticket separation, table/waiter/time attribution, print-request/reprint state, narrow viewport inspection and two-tab update verified. A follow-up soup order in the second tab changed the first tab total from R05.50 to R31.00 without reload.
- Browser print-request dispatch was exercised; OS driver output, paper/cutter behavior and physical handoff remain unverified. Browser tests do not replace real notebook/printer acceptance.
- The local preview uses a separate synthetic database on port 4005; delivery and Python workers are disabled. No deployment/push or live customer processing was performed.

Machine-readable working-tree evidence is in docs/evidence/restaurant-local.json. No sprint is marked complete by these local checks.

## Composition follow-up

The generated interface and migration follow-up is documented in [process composition](process-composition.md). Menu search now normalizes accent marks locally; Enter confirms the first suggestion without adding or sending an order. The typed term does not cause a LiveView search event. Main navigation is generated from published organization-owned processes. Old school-specific adapters remain compatibility code and are explicitly identified as migration work, not claimed as fully generic editor blocks.

## Sprint-plan reorganization — 2026-10-21

D-27 prioritizes architecture Sprints 09–11 before the preserved pilot work in Sprints 12–15. Current task references above use the new numbering; historical machine-readable evidence retains its original identifiers and source hashes. See the [roadmap mapping](../sprint_plan/first_customer_roadmap.md#scope-tracking).

## Retired operational history — Sprint 11

After the forward archival migration, unpaid sessions pinned to retired versions
are retained as archived, not settled. Their pending batches are archived without
claiming manual delivery. The daily report shows their captured non-cancelled
amount separately from open balances, paid sales and receipts; estimated requested
units still include that history. Archived sessions release resources and do not
block day closure. A current supported publication can open a new session on the
same resource. Historical paid sessions, cancellation totals, receipts and prior
day snapshots are preserved. See the [checkpoint review resolution](sprint11-first-checkpoint-review-resolution.md)
for the populated migration/restore test and operator procedure.
