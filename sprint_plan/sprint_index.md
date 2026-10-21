# Sprint progression

[Design index](../design/index.md)

Status: implementation in progress · Updated: 2026-10-21

Dependency-ordered increments without duration estimates. Sprints 00 and 01 retain their original single-organization evidence. Sprint 01A has migrated and verified the multi-organization foundation before Sprint 02, preserving existing records.

| Sprint | Outcome | Dependencies | Status | Tasks done | Actual start / finish |
|---|---|---|---|---|---|
| [00](sprint_00.md) | Foundation and PT-BR shell | None | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [01](sprint_01.md) | Versioned workflow runtime | 00; D-08, D-14 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [01A](sprint_01a.md) | Multi-organization foundation migration | 01; D-01, D-18–20 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [02](sprint_02.md) | Local permissions and concurrent collaboration | 01A; D-13 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [03](sprint_03.md) | Editor, interchange, authoring guide | 02; D-15 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [04](sprint_04.md) | Enrollment and parent portal | 03; D-05, D-10–12 | Done | 5/5 | 2026-10-20 / 2026-10-21 |
| [05](sprint_05.md) | Budgets, purchasing, field trips | 04; D-07 | Done | 5/5 | 2026-10-21 / 2026-10-21 |
| [06](sprint_06.md) | Confidential incident collaboration | 05; D-06 | Planned | 0/5 | — / — |
| [07](sprint_07.md) | Integrated demonstration and delivery | 06; D-09 | Planned | 0/5 | — / — |
| [08](sprint_08.md) | Optional isolated Python calculations | 07; D-16, D-17; readiness gate | Proposed / gated | 0/5 | — / — |

## Tracking

Sprint 08 is a post-proof-of-concept extension, not a requirement for completing Sprints 00–07. Keep it Proposed / gated until its use case, isolated hosting, and operating/security ownership are resolved. Do not add Python execution to the completed Sprint 01 or delay Sprint 02 for it.

Statuses: Planned → Ready → In progress → Review → Done. Blocked requires a concrete blocker and owner in the sprint file.

Check tasks only with evidence. Derive counts from task checkboxes; acceptance criteria are an additional gate. Record actual dates, evidence links, and remaining defects when status changes. Completed task counts alone do not mean Done.

All sprints use [shared completion rules](../design/07-verification.md). Scope changes update this index, the sprint, and the design register.
