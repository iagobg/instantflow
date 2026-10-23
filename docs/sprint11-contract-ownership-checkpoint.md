# Sprint 11 capability and ownership acceptance

Executed 2026-10-23 on discovery checkpoint ef4e96e. T03 and T04 are complete;
T02 performance and T05 combined recreation/recovery remain open.

The closed capability registry now enforces its declared dependency and conflict
metadata during complete validation. All 32 core-plus-optional subsets are checked:
24 valid combinations execute supported lifecycles; eight communications-without-
participants combinations produce indexed capability diagnostics. Drafts may retain
incomplete dependencies for correction. The portable metadata is checked against
the registry. Import, review and rendered editor publication agree; forged
publication cannot bypass the same validation.

Finance binding regressions execute actual reserves across two publications and
accounts. Removing an unused account is test-only fault injection: the unavailable
binding blocks effects, receipts and outbox changes and exposes an actionable setup
alert. The mapping editor identifies the budget path and can publish a repair.
Existing records retain their immutable account pin; neither old holds nor broken
pins are silently moved. Account archival is not a supported feature.

Workspace configuration and participant preview are now pure AuthoringPanels
components with explicit inputs. Their form IDs and authoritative LiveView/context
events remain covered. The obsolete guardian actor control is removed. Alongside
FieldInput, PaginationControls, Operations.ReadModel and scoped publication ownership,
this closes the touched cohesion work without a module-size rewrite.

## Acceptance evidence map

| Contract | Maintained evidence |
|---|---|
| Closed capabilities and portable metadata | capability_matrix_test: all 32 subsets; 24 supported lifecycle executions |
| Import/editor diagnostics and binding readiness | sprint11_binding_lifecycle_test: rendered dependency denial, pinned reserve, unavailable account and repair |
| Graph, references, effects and version vocabulary | definition, diagnostics, interchange, builder_contract, calculation_contract and finance definition tests |
| One transaction, late rollback, replay/revocation | builder_transaction and sprint11_operational_checkpoint tests |
| Async stale/cancelled/revoked results | calculations/runtime_test |
| Changed fields/stages/pages/payments and current grants | projections, participant_pages, pinned-navigation and participant-release checkpoint matrices |
| Real field transport and exact file release | field-surface and participant-release checkpoint reports |
| Context/component dependencies | participant_boundary_test, including the extracted authoring panels |
| Obsolete behavior disposition | sprint11-legacy-disposition-inventory: all classified; historical schemas/data retained |

Focused checks pass 17 tests (seed 421997) and 14 tests (seed 916851).
Full mix precommit passes 342 tests (seed 295089); asset build and whitespace checks
pass. Evidence records source and retained log hashes. Prior failed measurements and
intermittent session observations remain recorded in their original reports; this
checkpoint does not claim their cause was resolved. No serving database was changed.
