# Permissions and external access

[Design index](index.md)

## Model

Deny by default. Roles grant capabilities; department, assignment, requester/guardian relationship, stage, and classification restrict scope.

First require an active organization and membership in that organization. All subsequent permissions are local: an administrator in A has no implied role in B. A global user may have multiple independent memberships. Tenant administrators cannot view a global user directory, change other memberships, or disable a global account. Platform provisioning/suspension authority is separate and grants no default ticket access. See [organization isolation](11-organizations.md).

Evaluate separately: discover/list, summary, detail, section read/edit, create, comment visibility, assign, transition by edge, attachment/download, history, configure, publish, import, and export. Stage access does not imply transition authority; ticket access does not imply all-field access. Context functions enforce policy independently of hidden controls.

The platform policy model applies to any organization's roles and external participants. The following roles and parent portal illustrate it using the school demonstration; they are not mandatory roles or participant types for other organizations.

| Actor | Proposed scope | Exclusions |
|---|---|---|
| Parent | Own enrollment/verified child, corrections, public messages | Other families, internal reviews, incident detail by default |
| Teacher | Own trips/requisitions, incident submission and allowed follow-up | Finance approval, unrestricted incident search |
| Admissions | Enrollment verification | Finance approval, support notes |
| Department head | Academic approval within department | Other departments without grants |
| Finance | Granted payment/budget operations | Counselor notes |
| Operations | Assigned transport and receiving | Allocation changes |
| IT | Minimum identity for assigned provisioning | Unneeded admissions documents |
| Dean | Authorized triage and disciplinary section | Counselor-private notes without explicit grant |
| Counselor | Assigned cases/support section | Blanket incident visibility |
| Workflow administrator | Definition editing/publication | Automatic student-data access |

Proposed separation of duties: no finance-sensitive self-approval, including overlapping roles. Overrides, if required, need an explicit capability, reason, and audit event.

## Parent portal

Expiring invitations establish accounts; staff separately verify guardian relationships. Do not infer authority from matching names/domains. Parent A cannot discover Parent B through IDs, counts, search, events, files, or history.

Invitations and verified guardian relationships are organization-bound. An existing account must authenticate as the invited identity to accept a new organization membership. The same parent/student names at two schools create no automatic link. Scoped downloads, history, counts, and invitations must also reject foreign-organization IDs.

Use an explicit public projection: allowed submitted fields, public status, corrections, messages, and attachments. Internal stages may map to “Em análise”. Do not merely hide controls on an internal form.

## Live authorization and confidentiality

Authorize at mount, commands, refreshes, and downloads. A subscription is not a grant. Broadcast minimal invalidations and fetch authorized projections rather than sending full tickets to broad topics.

Revocation invalidates sessions, clears protected content, and removes subscriptions. Periodic/reconnect revalidation covers missed events. Previously delivered information cannot be recalled. Presence and counts follow record visibility; parents receive no staff presence by default.

Separate disciplinary and counselor sections. General history may show an authorized event without confidential text. No sensitive values in events, logs, URLs, or ordinary telemetry.

Retention, guardian disputes, and responsibilities for real student data remain open. The demonstration uses synthetic data and makes no claim of legal compliance.
