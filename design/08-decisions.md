# Decision register

[Design index](index.md)

| ID | Status | Question / decision | Direction | Needed by |
|---|---|---|---|---|
| D-01 | Confirmed | Organization scope | One organization initially | Foundation |
| D-02 | Confirmed | Customization | Administrator constrained visual editor | Editor |
| D-03 | Confirmed | Integrations | Explicit demo payments/notifications/provisioning | First slice |
| D-04 | Confirmed | Language and stack | PT-BR; Elixir/Phoenix LiveView; non-authoritative JS | Foundation |
| D-05 | Open | Guardian verification | Proposed: staff invitation and manual verification; multiple guardians | Sprint 04 |
| D-06 | Open | Incident/support visibility | Proposed: assigned counselor-private notes; curated parent communication | Sprint 06 |
| D-07 | Open | Budget/cancellation/price changes | Proposed: reserve at finance approval; commit at order; explicit reversals | Sprint 05 |
| D-08 | Proposed | Parallel branches now? | Sequential stages, independent sections | Sprint 01 |
| D-09 | Open | Hosting/load/timezone | Proposed: one deployment; 50 concurrent staff/10,000 tickets; America/Sao_Paulo | Sprint 07 |
| D-10 | Open | Parent self-registration? | Proposed: invitations only; no anonymous uploads | Sprint 04 |
| D-11 | Open | Parent-visible status/messages | Proposed: explicit public projection | Sprint 04 |
| D-12 | Open | File types/sizes/retention | Proposed: bounded private PDFs/images; synthetic data pending retention rules | Sprint 04 |
| D-13 | Proposed | Self-approval | Prohibit finance-sensitive self-approval | Sprint 02 |
| D-14 | Proposed | Definition changes | Immutable versions; existing tickets pinned | Sprint 01 |
| D-15 | Proposed following user suggestion | Interchange and LLM guide | Versioned JSON, draft-only imports, local mappings, shared validation; external LLM authorship | Sprint 03 |

## Recorded answers — 2026-10-20

The user chose one organization, a visual editor, and explicit simulations. The user also asked whether import/export and an LLM guide would be worthwhile; the design recommends and plans them, with D-15 kept Proposed.

Resolve guardian access/confidentiality first, budget semantics before finance, and hosting/load before delivery. Record future rationale here and update affected design/sprint criteria together.
