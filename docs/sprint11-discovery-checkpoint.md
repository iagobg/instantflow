# Sprint 11 bounded discovery and ownership checkpoint

Executed 2026-10-23 on operational-read revision 7ef5634. Scope: T02 remaining
process/participant/view/message discovery reads and the touched T04 navigation,
publication and pagination responsibilities. Full T02 measurements and remaining
T03–T05 acceptance remain open at this checkpoint.

## Authorized selection before pages

Workspace discovery now applies current role mappings in SQL to the latest
publication of each process before counting or paging. A history of participant
or curated-message declarations still requires explicit staff-workspace authority;
removing a page in a later publication cannot reveal the staff workspace to a
candidate external identity. Ordinary workspace discovery retains its declared-role
rule. Creation separately requires its declared creation roles and excludes retired
latest versions. Role mappings and actual memberships/grants are read freshly under
Tenant's existing authorization gate and tenant RLS.

Workspaces.get targets one process rather than loading every installed definition.
Workspace and creation lists have stable workflow-ID ordering and 25-result pages.
Navigation fetches at most 25 authorized ID/label shortcuts, without full definition
payloads. The Processos catalog has exact authorized counts, search and pages so
later processes remain reachable; direct later-workspace creation checks only the
selected process. The cross-process Solicitações creation menu is a bounded shortcut
with a link to the full process catalog. No second record-policy engine was added.

The previous unbounded Workspaces.latest read is removed after its two operational
callers move to a SQL candidate query capped at two rows, preserving the existing
unique-workspace versus ambiguous-workspace decision. Captured operational rows
still establish retained historical lineage where required.

The existing Projections service now counts/pages distinct participant-page and
view descriptors in SQL after its pinned policy predicates. Each 25-row option
page uses the newest admitted pin for duplicate process/key descriptors. Declaration order within each admitted pin is retained, including the default
triage view; workflow/version/ordinal/key ordering keeps pages deterministic. Existing
supported old pins remain discoverable even when the latest publication excludes
the actor. Participant entry cards include the process name. Global and per-process
view selectors, participant entry pages and curated inbox entries expose pagers.
Curated discovery compiles only versions referenced by that recipient's messages;
unused communications publications are no longer loaded for every inbox read.
Message recipient/relationship and snapshot rules are unchanged.

## Cohesive ownership

Layouts.app now renders supplied navigation and performs no context reads. The
authenticated lifecycle owns the small fresh navigation projection on mount,
parameters, events and authorization invalidation. Publication invalidation also
refreshes discovery screens. This is an ephemeral UI projection, not a persisted
permission cache; every protected read and command retains its own live gate.

Catalog publication has a transaction-scoped implementation shared by direct
publication and draft publication. The draft/version/audit remain in their owning
transaction; publication notification is emitted after the public transaction
returns. It no longer needs a nested public publication command. Current admin
validation, local ownership, revision conflict and immutable versions remain intact.
Shared PaginationControls owns accessible result counts and page buttons; generated
components retain their form/input IDs and contain no read or mutation calls.

## Maintained regressions

WorkspaceDiscoveryTest reproduces a targeted lookup fetching all 60 definitions
before the change. It now checks at most one fetched row for that lookup, 25-result
pages with exact 55-visible/5-hidden counts, stable last-page clamping, hidden-name
search denial, creation paging and fresh grant revocation. A historical participant
publication cannot become a staff workspace for an external candidate after its
participant page is removed.

DiscoveryPaginationLiveTest reaches a later process page and creates a record
through its direct generated workspace. Publication updates an already open
navigation projection; granting and revoking a scoped role adds/removes its link.
Thirty independently configured participant/message processes verify later portal,
inbox and view choices, exact counts, generated entry links and live relationship
revocation. Query and component boundary checks remain mandatory.

The final focused discovery/authoring group passes 22 tests (seed 763394); the
additional configured-view/participant/operation/curated group passes 27 tests
(seed 229312). Full checks and source/log hashes are recorded in
[evidence](evidence/sprint11-discovery-checkpoint.json).

No scale result is inferred from bounded result counts alone. Complete supporting
volume, policy/planning, full VM memory and browser measurements against the fixed
budgets remain T02's final gate. Sprint progress remains In progress, 1/5. No serving
migration, deployment or destructive reset was performed.

## Validation follow-up

The first full run (337 tests, seed 723536) exposed an ordering regression: sorting
view keys alphabetically made an incident workspace choose board before its declared
triage default. The failed log is retained. Discovery now carries JSON ordinality
and orders descriptors within the newest admitted pin as declared. The incident,
projection, participant and later-page group passes 14 tests (seed 421586). This was
a concrete default-view regression, not attributed to the earlier token observation.

The full same-seed precommit rerun passes 337 tests (seed 723536). Asset build and
whitespace checks pass. No token diagnostic or validation change was needed for
this ordering correction.
