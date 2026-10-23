# Orçamentos, compras e passeios — demonstração

Sprint 11 D-32 retired the dedicated **Orçamentos** route. Shared-budget
commands and the rules below remain supported through configured
`finance_setup`/`finance_summary` blocks in **Processos** and generic records in
**Solicitações**. Old screen instructions are historical; see the
[retirement checkpoint](sprint11-retirement-checkpoint.md).

Sprint 05 uses synthetic data and integer BRL cents. No provider receives an order, no funds move, and no external credit is issued.

## Setup and permissions

Run `mix ecto.migrate -r Instantflow.OperatorRepo` and `mix run priv/repo/seeds.exs` with the existing `DEMO_PASSWORD` environment variable. Seeds preserve passwords and existing records. Each school receives its own **Atividades e materiais** account with a one-time 100,000-cent allocation and independent **Requisição de materiais e bens** / **Aprovação de passeios** template copies. Running seeds again does not allocate twice.

Open **Orçamentos**. Administrators create accounts and configure profiles in **Equipe e convites**. Accounts belong to a local department. Profile permissions apply only to that department: **Financeiro** reserves; **Alocação financeira** adds allocations; **Estorno financeiro** explicitly credits posted spending. These permissions are separate. Financial viewers are the local finance, allocation, reversal, and head profiles for the account department. Administration alone grants no balance or reversal access. Allocation requires a reason; reservations and reversals prohibit requester self-approval even when profiles overlap.

Horizonte demo: docente creates, coordenacao approves, financeiro reserves, operacoes orders/receives, and direcao reviews safety and separately holds the finance reversal permission. Addresses end in @escola.example. The administrator has allocation permission. Aurora's admin@escola.example is a local requester, financeiro@aurora.example reserves, and gestao@aurora.example carries head/operations/safety/reversal and allocation profiles in the corresponding local departments. These grants do not carry between schools.

## Purchase walkthrough

1. As the teacher, open **Solicitações**, create a requisition, and save the description/specifications, justification, positive quantity, and cost in cents. A requisition represents one quantified item or homogeneous group. Use separate requests for independently received item types/units.
2. Submit, then approve as coordination. Finance chooses **Reservar orçamento**. Insufficient available funds leave the request at finance review with no receipt, hold, spending, or stage change.
3. As operations, save a fictional order reference and choose **Confirmar pedido simulado**. The full reservation converts to spending in the same transaction. Available funds do not decrease a second time.
4. Enter cumulative received quantity. Values below zero or above ordered quantity fail. Partial delivery saves but cannot complete; the exact total enables **Concluir recebimento**.
5. Before ordering, use cancellation with a reason to release the hold. To change price, quantity or specifications, choose **Revisar proposta e renovar aprovações**, save the changed proposal and repeat academic/finance approval. This releases the old reservation and clears downstream order/safety/delivery forms. There is no silent price increase after reservation.
6. After ordering, cancellation requires **Estornar com crédito explícito** by the separate reversal profile and a reason attesting a fictional full credit. It removes committed spend once, records the actor/reason and ends at cancelled. Partial credits, partial financial settlement and post-order price amendments are outside this demo; reverse and submit a fresh request when appropriate.

## Trip walkthrough and views

A teacher provides itinerary, date, destination, participant count, cost and risk measures. Coordination approves academic value; finance reserves; operations records transport; direction checks the safety confirmation before approval converts the reservation to spend. Each stage is a separate authorized command. Changes to the proposal return it to the initial stage and repeat all reviews; previous transport and safety values are cleared. The approved trip can only be cancelled through explicit full reversal.

In **Solicitações**, choose the template's table, **Gargalos por etapa**, **Atribuições por departamento**, or **Calendário de passeios propostos e aprovados**. The calendar is a date-sorted agenda showing dates and current stage, including proposed/approved/cancelled distinctions, with 25 authorized records per page and the normal stage filters. Assignment views show the currently assigned department; stage boards show scoped counts. Dates remain date-only; no timezone conversion is applied. No student consents, actual transport booking, arbitrary assignment override or emergency guarantee is included.

## Accounting and recovery

Available = allocated − reserved − spent. Commands lock the ticket and sections first, then the shared account, and commit the hold, totals, immutable ledger entry, workflow event, command receipt and durable refresh intent together. Two finance users approving different templates contend on the same account row. Database checks additionally prevent negative or overdrawn totals. Each ticket has at most one current hold; re-review may reuse a released hold. Retry keys compare command payloads and return the original result. Allocation keys are namespaced by actor; changed payloads fail. Allocation and ledger keys cannot collide.

Workflow refreshes travel through the existing tenant-bound durable outbox, including budget invalidation. Direct allocations broadcast only after commit. Budget screens independently reauthorize reads and reconcile every 30 seconds; missed events never become authoritative balances. Permission revocation clears forms/totals through the session hook. Topics carry only invalidation signals. Sections, calendar rows and counts use the pinned template policy and active organization, including shared user accounts. Budget bindings and composite ownership foreign keys reject foreign accounts/tickets/departments; RLS denies missing/wrong tenant context.

The ledger is append-only and forward migrations preserve existing records. Use the coordinated backup/restore procedure in [organization operations](organizations-operations.md). This is budget tracking with full reservation/posting/reversal, not a general accounting ledger, real purchasing system, tax calculation, stock system or production financial certification.

## Authoring

Finance is the additive format-1.0 finance capability. Bindings may declare type: budget; imported definitions contain symbols only and need local budget mapping before publication. Transition finance specifications select reserve, post, release, reverse or complete, an account_binding, and typed amount_field (BRL money) or quantity_field/received_field references. Effects run synchronously in the runtime transaction, never in the external-delivery worker. The advanced JSON editor authors these specs; ordinary typed edits preserve them and the local mapping controls resolve accounts. Unknown effects, references, currencies and foreign account mappings fail validation. Immutable existing versions keep their original semantics.

## Evidence

[Finance tests](../test/instantflow/finance/accounting_test.exs) cover full paths, replay, explicit reversal, insufficient budget, revised costs, delivery bounds, trip prerequisites, self-approval and interchange/authoring preservation. [Live tests](../test/instantflow_web/live/budgets_live_test.exs) cover committed totals across viewers, revocation, forged allocation attempts, parent/staff denial, calendar and assignments. [Runtime-role tests](../test/instantflow/runtime_role_test.exs) overlap two actual non-owner connections behind an account-lock barrier across purchase/trip templates; exactly one reservation commits. It also checks shared-finance-user isolation, raw RLS, composite ownership and immutable ledger entries.

A browser smoke check verified the existing parent session receives zero accounts, no amounts, no allocation controls and no finance navigation at the direct budget URL. Staff interactions and calendar rendering were verified with LiveView tests; no exhaustive manual browser, accessibility, device or load certification is claimed.
