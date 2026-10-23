# Sprint 11 field/surface checkpoint

Executed 2026-10-23 on revision 6651f74. Scope: T03's supported field/surface
matrix and the touched T04 generated-control responsibility. Full T03 and T04
acceptance remain open.

## Supported matrix

Every projection still requires current record/section/page authority. A declared
field, view column or message source never grants that authority.

| Type | Ordinary form | Participant form | View column | Filter/sort | Calendar source | Curated message source |
|---|---|---|---|---|---|---|
| short_text | Text, up to 200 characters | Same | Yes | Yes | No | Yes |
| long_text | Textarea, up to 10,000 characters | Same | Yes | No | No | Yes |
| integer | Whole signed number, safe integer range | Same | Yes | Yes | No | Yes |
| money | Whole nonnegative BRL centavos, safe integer range | Same | Yes | Yes | No | Yes |
| date | ISO civil date | Same | Yes | Yes | Yes | Yes |
| datetime | ISO instant with explicit offset | Same | Yes | Yes | Yes | Yes |
| boolean | Blank, Sim or Não | Same | Yes | Yes | No | Yes |
| single_choice | Blank or one declared option | Same | Yes | Yes | No | Yes |
| multiple_choice | Declared options plus hidden empty sentinel | Same | Yes | No | No | Yes |
| directory_reference | Bound verified participant/subject selector | Rejected | Yes, section-authorized value | No | No | Rejected |
| attachment | Dedicated declared-policy document controls | Selected declared-policy document controls | Yes, section-authorized value | No | No | Rejected |

View column support describes the declaration and authorized stored value. It does
not release file bytes or expand participant directory-reference editing. Document
URLs still use the separate exact-field release gate; local references still need
current directory ownership/eligibility. Directory and document rendered flows are
covered by their existing dedicated tests, retained in this checkpoint's focused
regression group. The new scalar matrix exercises all nine other types end to end.

Optional text clears to the empty string; multiple choice clears to an empty list;
other scalar fields clear to nil. Required transition/message guards continue to
reject absent values. Boolean false remains an explicit present value. Multiple
choice strips only the empty transport sentinel; undeclared and repeated options
are rejected. Money is integer centavos, not decimal currency parsing. Datetime
keeps its explicit offset instead of silently converting to datetime-local.

## Reproduced defects and shared controls

The baseline matrix reproduced three missing-clear controls (18 tests, 3 failures,
seed 811467): ordinary single choice, participant single choice and participant
boolean had no blank option. Consequently an optional value could not be cleared
through its rendered selector. No runtime validation change was required.

FieldInput now owns the common input presentation: input types, select options,
multiple-choice controls, numeric constraints and the explicit-offset placeholder.
Both generated staff and participant forms use that pure component and the existing
core input component. FieldValues remains the shared transport converter; business
validation and authorization stay in their current contexts. Existing form/input
IDs, event names, revision/draft handling and separate document/directory services
are preserved. Participant numeric controls now expose the same whole-number and
nonnegative-money hints as ordinary forms; the server remains authoritative.

## Executable evidence

sprint11_field_surface_matrix_test.exs contains 18 cases: nine scalar types on
ordinary and participant surfaces. Each case imports a portable definition,
revises its field through the typed editor, configures local bindings through the
rendered mapping form, publishes, exports and imports a copy without local IDs.
It then creates a record, verifies an external relationship and opens correction
through supported commands. No business rows are inserted directly.

The rendered form submits initially empty, typed and cleared values. Normal inputs
are checked against actual rendered controls, including the multi-select hidden
sentinel. Forged invalid payloads bypass client input constraints and must fail
without changing stored values. Boolean cases exercise true and false; multiple
choice also rejects duplicates. A fresh LiveView mount verifies reconstructed
selected options and input values. Authorized view cells preserve typed values and
clearing. The actual release form creates a curated snapshot; pending content is
hidden, simulated successful delivery reveals it, and clearing the record leaves
the delivered snapshot unchanged. The recipient inbox renders the released value.

field_surface_contract_test.exs adds 13 tests. It checks the eleven-type portable
schema/authoring vocabulary, core-only scalar definitions, all declared column,
filter/sort/calendar, participant and message combinations, and identical semantic
validation after JSON encoding/decoding. Invalid participant or message attachment/
directory-reference sources fail both import and publication without publishing a
version. Their actionable diagnostic paths are retained.

The focused group includes directory-reference selection/denial, declared private
document release, existing selected/omitted document regressions, multiple-choice
transport and collaboration conflict/draft behavior. It passes 45 tests (seed
67810). Full precommit passes 325 tests (seed 932154); asset build and whitespace
checks pass. Full validation and hashes are recorded in
[evidence](evidence/sprint11-field-surface-checkpoint.json).

## Remaining gates

This matrix does not close the wider T03 multiple-page authorization parity,
capability/mixed-version/account/binding matrices, or asynchronous stale-result
acceptance. T02 browser/full BEAM/supporting volumes, residual T04 ownership and
T05 full recreation/recovery remain open. Sprint 11 stays In progress, 1/5.
Previously observed intermittent LiveView token/reload behavior remains unexplained;
passing tests do not establish its cause or resolution. No serving migration,
deployment or destructive reset was performed.
