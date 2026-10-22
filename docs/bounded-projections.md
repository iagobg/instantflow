# Bounded runtime projections

Implemented 2026-10-22 as the initial S10-T02 query checkpoint. Sprint 10 is in
progress; this increment does not complete T02 or the T01 participant slice.

## Ownership and callers

`WorkflowRuntime.Projections` owns authorized record selection, count semantics,
page bounds and configured table/board row projection. `PolicyQuery` compiles
the existing pinned section actor contracts into Ecto predicates. It uses the
same current profiles, departments, verified relationships and named assignment
eligibility as the command/detail policy. Its outcome parity is covered by
participant, staff grant, confidential assignment, subject-only and tenant tests.
The historical parent/guardian exclusions remain explicit compatibility rules.

`WorkflowRuntime.search` and `WorkflowCatalog.Views` delegate to this boundary.
No generated query calls Enrollment, Incidents, or a template-selected service.
LiveViews render projections and pass filter/page inputs; they do not decide
record policy. The old `WorkflowRuntime.list` remains a legacy read path for the
Sprint 11 residual migration gate. New surfaces must use bounded queries.

## Supported query contract

| Input | Meaning and bound |
|---|---|
| `workflow_id` | Optional positive database ID; foreign or malformed IDs return an empty result. |
| `stage` | Optional exact pinned stage key, bounded to 100 characters. |
| `query` | Case-insensitive literal substring of ticket ID or pinned process name, bounded to 100 characters. No section values are searched. |
| `page` | Positive page number, clamped to the last available page; invalid values select page 1. |
| View key | Must exist in the record's pinned definition and have at least one readable column; otherwise the record contributes no rows or metadata to that view. |

Page size is fixed at 25. Selection always orders by descending ticket ID, a
unique deterministic tie-breaker independent of private field values. There is
no caller-controlled field ordering in this increment. Configurable typed
filter/sort declarations and expanded calendar/urgency behavior remain T02 work.
Date-only cells remain date-only values; this service does not convert them into
instants or infer timezone semantics. A view row retains its pinned type.

For record search, `total`, stage `counts` and `stage_labels` describe authorized
records before the user stage/text filters, within the requested workflow.
`filtered`, `page` and `pages` describe the filtered subset. For configured
views, `total` is the filtered authorized total for that view; stage options and
counts are pre-filter within that authorized view. Stages from hidden records
never contribute counts, labels or filter choices. If a stage key has several
authorized pinned labels, its filter label joins the distinct labels in sorted
order; individual rows retain their own pinned label.

View discovery uses the same record and readable-column predicates, in SQL.
It emits distinct view/version metadata rather than loading ticket rows. A
view made entirely of unreadable fields is absent from options and totals.
Discovery does not require record creation permission. Generated process pages
use these options, paginate through common controls, and can still select an
old view when a new publication removes it. This is view compatibility evidence;
the fuller participant page/field/stage removal fallback remains T01 work.

## Authorization, batching and bounds

Every operation enters `Tenant.read`, reloads current membership/grants under the
shared authorization gate and applies organization RLS. The gate covers selection,
counts and projection together. Revocation uses the existing exclusive gate and
is honored on the next operation, including when a caller retains an old scope.
A declared view never grants a section or record permission. Subject eligibility
and a verified relationship alone grant no access.

One catalog query loads the tenant's relevant workflow definitions, then compiles
their pinned actor policies. SQL applies those policies before aggregation,
user filtering, ordering and LIMIT/OFFSET. No ticket list is loaded to filter or
paginate in Elixir. Catalog compilation scales with published versions; this is
not a claim of customer-volume readiness. Sprint 11 owns measurement and tuning.

For configured rows, one query fetches only readable sections belonging to the
selected page, and one query resolves its department labels. Hidden sections do
not leave PostgreSQL. Section rows are bounded by the 25 selected tickets and
the definition's section limit. There are no per-ticket version, section,
relationship, assignment or department lookups. Unredacted catalog definitions
and local bindings never enter the public search result.

## Evidence and next checkpoint

- `test/instantflow/workflow_runtime/projections_test.exs`: 29 accessible records
  mixed with 45 newer hidden records, two pinned versions, stable paging and
  count semantics, unchanged query count from a one-record baseline, a single
  readable-section batch, hidden values absent even from fetched query results,
  revocation, named assignments, parent staff grants and subject-only denial.
- `test/instantflow/tenant_isolation_test.exs`: shared identity across organizations,
  guessed foreign workflow IDs, tenant-local records and view options.
- `test/instantflow_web/live/generated_projection_live_test.exs`: non-creator
  participant sees 26 authorized records through two pages, internal view metadata
  and unrelated records are absent, and an old view survives a second publication.
- Existing configured-view and corrected Sprint 09 regressions remain required.

The [machine-readable evidence](evidence/sprint10-query-checkpoint.json) records
validation results and source hashes. All fixtures use synthetic data and supported
import, mapping, publication, invitation and relationship commands.

The next checkpoint, T01's independently named correction/document workflow, is
now implemented and reviewed in [declared participant pages](participant-pages.md).
That checkpoint adds page admission before SQL selection and keeps projection-only
participants out of the broader generic lists/views for those pinned versions.
The original query-checkpoint evidence remains a historical snapshot; participant
checkpoint evidence identifies the combined current tree. Configured dashboard,
finance and communication expansion remains open.
