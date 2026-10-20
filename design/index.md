# InstantFlow design

Status: planning draft · Updated: 2026-10-20

Build a modular workflow application using Elixir and Phoenix LiveView. Demonstrate reuse through four school processes, internal collaboration, and a restricted parent portal.

## Confirmed requirements

- User-facing UI, validation, notifications, accessibility labels, and demo content are PT-BR. Engineering documents and identifiers may be English.
- Multiple isolated organizations, each with its own departments, memberships, workflows, and records.
- Administrators customize workflows through a constrained visual editor.
- Payments, notifications, and provisioning are explicitly simulated.
- Live dashboards, server-authoritative writes, concurrent users, granular permissions, and cross-department transitions are core.
- Cover enrollment, field trips, incidents, and purchasing.

The user additionally proposed template import/export and LLM-assisted authorship. This draft recommends including them through the same validated model as the editor.

## Document map

1. [Product scope](01-product.md)
2. [Architecture](02-architecture.md)
3. [Workflow engine](03-workflow-engine.md)
4. [Permissions](04-permissions.md)
5. [Concurrency and UX](05-concurrency-ux.md)
6. [School templates](06-school-templates.md)
7. [Verification](07-verification.md)
8. [Decision register](08-decisions.md)
9. [Import/export](09-template-interchange.md)
10. [PT-BR authoring guide](workflow_authoring_guide.pt-BR.md)
11. [Illustrative template](examples/simple_approval.json)
12. [Sprint progression](../sprint_plan/sprint_index.md)
13. [Custom Python automation: judgment and staged scope](10-python-automation.md)
14. [Organization isolation and migration](11-organizations.md)

Confirmed means explicitly requested or answered. Proposed means a working design choice. Open questions have IDs in the decision register. Sprints 00 and 01 were implemented against the former single-organization scope. The application is not yet multi-organizational: Sprint 01A migrates that foundation before Sprint 02. Consult the sprint index for evidence. Sprints are increments without time commitments. The interchange example remains illustrative until schema/validator implementation. Python is a gated later extension, not an existing capability.
