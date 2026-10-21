# Sprint 04 — Enrollment and parent portal

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 03; D-05, D-10, D-11, D-12

Goal: complete the first school slice with restricted external participation.

## Tasks

- [x] S04-T01 Implement guardian links, invitations, and parent projections.
- [x] S04-T02 Implement private attachment lifecycle, quarantine/validation, and downloads.
- [x] S04-T03 Configure enrollment, corrections, placement, and department handoffs.
- [x] S04-T04 Connect labeled simulated payment, notification, and provisioning.
- [x] S04-T05 Verify unrelated families, internal roles, mobile forms, and failure/retry.

## Acceptance criteria

- Parent submits, corrects, and follows permitted status to completion.
- Parent A cannot access Parent B through lists, IDs, files, history, counts, or events.
- Required unready files prevent verification; unauthorized downloads fail.
- Finance completion updates IT's queue; provisioning failure stays pending with retry status.
- Simulations are labeled; retries do not duplicate receipts/provisioning.
- Internal comments and assessments remain absent from external projections.
- Parent accounts shared across schools have independent local guardian links; invitations, private object keys, uploads, and downloads reject foreign organization IDs. Switching school cannot reuse the previous school's draft or documents.

## Progress

Actual start / finish: 2026-10-20 / 2026-10-21  
Evidence: `mix precommit` passed: **113 tests, 0 failures**, compilation warnings-as-errors, unused lock check and formatting. `mix assets.build` passed. Local forward migrations applied without resetting existing records; seed executed twice successfully.  
Blockers: none for the synthetic-data Sprint 04 demonstration. D-05 and D-10–12 adopted as implementation defaults under the continuation authorization, not separately supplied product answers. Production guardian disputes, malware scanning and retention remain a separate readiness gate.  
Handoff: enrollment reference slice and restricted external-access pattern; Sprint 05 is next.

### Delivery evidence

- T01: [enrollment context](../lib/instantflow/enrollment.ex), [guardian links](../lib/instantflow/enrollment/guardian_link.ex), [invitation acceptance](../lib/instantflow/identity.ex), [parent portal](../lib/instantflow_web/live/enrollment_live.ex). Staff invitations, independent local links, separate manual verification, multiple guardians, expiry/reuse rejection and immediate link revocation. Parents receive an allowlisted projection; generic internal request/history/count APIs deny parent membership access.
- T02: [private document context](../lib/instantflow/private_documents.ex), [download controller](../lib/instantflow_web/controllers/document_controller.ex), [lifecycle tests](../test/instantflow/enrollment/documents_test.exs). Private bytea storage with random object keys, 5 MiB/20-active-object limits, quarantine, bounded format/digest checks, staff release/rejection, deletion and 30-day synthetic expiry. Parent file access additionally requires the verified family and public application field. Required unready files prevent verification. No antivirus or real-document authenticity claim.
- T03: [enrollment template](../priv/workflows/enrollment.json), [runtime](../lib/instantflow/workflow_runtime.ex), [policy](../lib/instantflow/workflow_runtime/policy.ex), [authoring/interchange tests](../test/instantflow/enrollment/definition_test.exs). Parent correction/resubmission, admissions verification, private academic assessment, minimal IT identity, department-bound queue handoffs, guarded completion and immutable version pinning. Template symbols survive typed editor controls and interchange; unknown bindings and static operational-file constants fail validation.
- T04: [delivery](../lib/instantflow/delivery.ex), [reference-slice tests](../test/instantflow/enrollment/enrollment_test.exs). Labeled simulated payment, provisioning and notifications; finance completion assigns IT atomically. First provisioning attempt fails and remains pending at its stage; the same intent succeeds after explicit authorized retry. Repeated commands return one receipt/result and create one provisioning intent.
- T05: [LiveView and HTTP tests](../test/instantflow_web/live/enrollment_live_test.exs), [runtime-role tests](../test/instantflow/runtime_role_test.exs). Unrelated families and schools cannot discover IDs, counts, files, history or event payloads. Shared identities need independent verified links in each school. Route changes clear drafts/uploads, revoked live forms redirect, and unauthorized downloads return 404. Real non-owner connections verify RLS/composite ownership and overlap two guardians' saves behind a ticket-lock barrier; one wins and one conflicts. An exclusive revocation barrier denies the queued parent mutation after commit.
- Mobile browser at `http://localhost:4000/o/horizonte/matriculas/1`: fictional parent fields saved and survived reload at 390×844; document width and scroll width both 375 CSS pixels, with no horizontal overflow. Aurora's independent form remained blank. Parent controls exclude internal analysis, invitation administration and staff history. Browser upload and the full staff path are covered by LiveView/context tests, not claimed as a manual end-to-end browser run. A browser-automation confirmation-dialog stall prevented completing additional link-click checks; direct navigation and server-side route reset tests succeeded. This is not a physical-device/accessibility/load certification.
- Legacy forward migration and full multitenant restore rehearsal passed in new isolated databases `instantflow_rehearsal_old_0d3de7be8f64` and `instantflow_rehearsal_restore_0d3de7be8f64`; original values, tenant schema and rollback refusal were preserved. Backup: ignored `.local/backups/rehearsed-multiorg-0d3de7be8f64.dump`. This rehearsal validates legacy preservation/schema recovery; it does not claim a populated private-object restore exercise.

Setup, walkthrough and operating limits: [enrollment and private documents](../docs/enrollment.md). No real provider calls, money movement, directory lookup or Python execution are introduced.
