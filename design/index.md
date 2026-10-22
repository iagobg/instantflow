# InstantFlow design

Status: Sprints 00–09 complete; private academic Python deployment verified and enabled; Sprints 10–11 architecture priority; Sprints 12–15 customer delivery planned · Updated: 2026-10-21

Build a general-purpose, multi-organization workflow platform using Elixir and Phoenix LiveView. Organizations across different sectors configure their own processes, forms, permissions, and live dashboards. Four school workflows provide the initial demonstration, including cross-department collaboration and an external-participant portal illustrated by parent access.

## Confirmed requirements

- User-facing UI, validation, notifications, accessibility labels, and demo content are PT-BR. Engineering documents and identifiers may be English.
- Multiple isolated organizations, each with its own departments, memberships, workflows, and records.
- Administrators customize workflows through a constrained visual editor.
- Payments, notifications, and provisioning are explicitly simulated.
- Live dashboards, server-authoritative writes, concurrent users, granular permissions, and cross-department transitions are core.
- Cover enrollment, field trips, incidents, and purchasing.

The user confirmed template import/export and an LLM authoring guide in Sprint 03. They use the same validated model as the editor.

## Document map

[First real customer roadmap](../sprint_plan/first_customer_roadmap.md) adds proposed assisted onboarding, shared-database demo controls, real delivery and operational acceptance gates. Existing simulation and academic hosting decisions remain in force until those gates are implemented and accepted; this documentation does not enable customer operation.

1. [Product scope](01-product.md)
2. [Architecture](02-architecture.md)
3. [Workflow engine](03-workflow-engine.md)
4. [Permissions](04-permissions.md)
5. [Concurrency and UX](05-concurrency-ux.md)
6. [School demonstration templates](06-school-templates.md)
7. [Verification](07-verification.md)
8. [Decision register](08-decisions.md)
9. [Import/export](09-template-interchange.md)
10. [PT-BR authoring guide](workflow_authoring_guide.pt-BR.md)
11. [Illustrative template](examples/simple_approval.json)
12. [Sprint progression](../sprint_plan/sprint_index.md)
13. [Custom Python automation: judgment and staged scope](10-python-automation.md)
14. [Organization isolation and migration](11-organizations.md)

Confirmed means explicitly requested or answered. Proposed means a working design choice. Open questions have IDs in the decision register. Sprints 00 and 01 were implemented against the former single-organization scope; Sprint 01A migrated the foundation to isolated organizations, followed by Sprint 02 collaboration and Sprint 03 authoring/interchange. Consult the sprint index for evidence. Sprints are increments without time commitments. The delivered schema, catalogue and examples define portable format 1.0. Python is a gated later extension, not an existing capability.

Sprint 04 delivery: [enrollment operations and private documents](../docs/enrollment.md), with verified local guardian links, explicit parent projections and synthetic file limits. [Sprint evidence](../sprint_plan/sprint_04.md).

Sprint 07 delivery: [integrated demonstration](../docs/demo.md), [release-gate evidence](../docs/release-gates.md), [local performance](../docs/performance.md) and [deployment boundaries](../docs/deployment.md). Sprint 05 finance and Sprint 06 incident evidence are in the sprint index.

- [Process composition and generated interfaces](../docs/process-composition.md): organization-owned definitions, page/block authoring, generic URLs and legacy migration limits.

- [Modularity review and extension rules](../docs/modularity-review.md): current buildability matrix, capability contracts and remaining domain dependencies.

- [Builder architecture contract](../docs/builder-architecture-contract.md): Sprint 09–11 ownership, execution, publication and recreation requirements; [execution contracts](../docs/builder-execution.md) and [Sprint 09 completion](../docs/participants-and-documents.md).
