# Sprint 07 release-gate evidence — 2026-10-21

The final local mix precommit passed 136 tests with zero failures, including runtime-role independent-connection races. Production assets/release build, isolated integrated recovery and legacy migration recovery passed. No production deployment or real student data was used.

| Gate from design/07-verification.md | Evidence |
|---|---|
| 1. Four workflows and corrections/rejections | Enrollment, finance, incident and runtime context tests; integrated full walkthrough of all four in scripts/rehearse_delivery.exs; [recovery outcomes](evidence/sprint07-recovery.json). |
| 2. Author and import/export a fifth workflow | Template/interchange and TemplatesLive tests; integrated fifth space-request creation, publication, execution, export/import, mapping and independent Aurora customization. |
| 3. Family confidentiality | Enrollment/documents context and EnrollmentLive tests; integrated unrelated-parent and generic-parent runtime denial plus verified guardian upload. |
| 4. Conflicts, independent sections and convergence | CollaborationLive tests; runtime-role independent connections for same/different-section and save/approval races; refresh delivery rollback/burst/outcome tests. |
| 5. Atomic approvals and funds | Runtime-role competing transition, duplicate command and cross-template budget races; finance accounting tests verify balances, immutable entries and replay. |
| 6. Explicit simulations | Enrollment, request and incident LiveView tests verify labeled payment/provisioning/communication state and failure/retry; integrated fail-once recovery. No real provider calls. |
| 7. Attributable private history | Runtime, enrollment, finance and incident tests verify receipts/events/assignments, reasons, delivery attempts, restricted projections and private notes exclusion. |
| 8. PT-BR and basic accessibility | Manual browser smoke at 1280×720 and 390×844, keyboard skip-link/main focus and support-save persistence. App file labels now explicit PT-BR; input errors use shared PT-BR components. Mobile request/budget pages had no page overflow; wide budgets scroll within their container. Urgency has text and aria-live status. This is targeted smoke, not a professional accessibility/device certification. |
| 9. Portable semantics, no grants/data | Catalogue/interchange/definition tests for malformed/oversized/deep/executable input and local mapping; integrated import proves distinct drafts, rejected foreign mappings and no change to source publication. |
| 10. Organization boundaries | Tenant-isolation and actual runtime-role tests cover RLS, absent/wrong context, pooled reuse, lifecycle, jobs, quotas, files, revocation and overlapping identities. Integrated independent Aurora customization and shared-user denial; [uneven load](evidence/sprint07-mixed-uneven.json) reports each school. |
| 11. Forward migration preserves data | scripts/rehearse_01a.py compares original rows across forward migration, multitenant backup restore and destructive rollback refusal; [legacy outcomes](evidence/sprint07-legacy-recovery.json). Populated current-schema restore also compares every table count and canonical-row digest, including file bytes and history. |

## Browser smoke observations

On the isolated synthetic browser database, the dean could not see counselor fields; the assigned counselor could edit and persist support notes but not see discipline fields. An unrelated teacher's direct incident URL returned to the authorized request list and the private incident did not enter counts. Switching the shared identity from Horizonte to Aurora removed administrator navigation/allocation controls. Parent confinement and simulated failure states are also covered by dedicated LiveView/context suites. Browser smoke used a separate loopback listener; temporary tabs, viewport override and listener were closed afterward.

## Delivery and measurement

[Demo reproduction](demo.md), [deployment/limits](deployment.md), [measured workload and failed-baseline fixes](performance.md), [production release smoke](evidence/sprint07-release.json). The release smoke verifies runtime-role startup, HTTP login and both digested JS/CSS assets; local success does not certify a remote TLS/proxy/database topology. Recovery databases/backups remain isolated and private. No serving data was reset or overwritten. Whole-database recovery is distinct from unsupported tenant-selective restore.

Sprint 08 now has a disabled-by-default script catalogue and asynchronous calculation implementation for the user-approved same-VPS gVisor university topology. Its [readiness assessment](python-readiness.md) and [operator guide](python-calculations.md) keep activation/completion gated on actual ARM host isolation and recovery evidence. The Sprint 07 evidence above predates these changes. Production operating owners, real providers, off-host backup policy and student-data readiness remain as documented limitations.
