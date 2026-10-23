# Enrollment, guardians and private documents

**Historical Sprint 04 walkthrough.** Sprint 11 D-32 retired the Enrollment
context, guardian invitation writer and Matrículas routes described below.
Current demos use **Processos**, the enrollment's generated staff page and
`family_portal`, generic external invitations and explicit participant
verification on the record. Attachments require a declared document policy.
The forward migration preserves old records as read-only history; the seed
publishes a supported replacement when the latest version is retired.
See the [current retirement checkpoint](sprint11-retirement-checkpoint.md) and
[participant/document guide](participants-and-documents.md). The remaining text
records the original behavior rather than instructions for current entry points.

Sprint 04 delivers the first school demonstration slice. Its template passes the same publication, graph, schema and semantic checks as editor/imported templates. Sequential stages use the generic workflow runtime and immutable version pinning; domain vocabulary and the external projection live in `Enrollment` and `priv/workflows/enrollment.json`.

## Setup and demonstration

Apply forward migrations with `mix ecto.migrate -r Instantflow.OperatorRepo`, then run `DEMO_PASSWORD=... mix run priv/repo/seeds.exs`. Use the environment-variable handling described in README; do not commit credentials. The repeatable seed preserves all earlier records and passwords, adds independent enrollment templates and two synthetic families to Horizonte and Aurora, and grants the Horizonte secretary/academic/finance/IT staff their matching local department profiles. Administrators receive an explicit admissions grant for demonstration setup. Existing workflow copies are never overwritten.

Parent accounts are `responsavel.a@escola.example` and `responsavel.b@escola.example`. Both have independent school-local guardian links. Only newly created accounts use the supplied seed password. In the current local verification workspace, the generated synthetic-account password is in ignored `.local/sprint04-demo-password`; it is not a shipped credential.

1. Open **Matrículas** as an administrator or admissions colleague with the template's local admissions department profile. Administrators can install the model after selecting four local departments. A matching profile is required to operate records; publishing a model grants no record access.
2. Open a matrícula and generate a simulated guardian invitation. The code appears once, expires after 48 hours and is stored as a digest. There is no outbound email. Activate at `/convite`. Existing accounts must sign in as the invited identity first. Acceptance establishes an unverified local link; staff must separately choose **Verifiquei o vínculo**. Multiple guardians need separate links and verification. Revocation removes only that link's access.
3. As the parent, fill the student's fictional name, guardian name and year. Upload a fictional PDF, PNG or JPEG of up to 5 MiB, select its object and save the form. Uploads enter quarantine. A parent can submit into document review while the file is quarantined, but verification cannot advance until every required attachment is ready. Corrections reopen the same application form with optimistic revision checks. Unsaved edits stay in that tab and must be saved or discarded before submission.
4. As admissions, open **Matrículas** to release or reject the synthetic file. The manual release attests staff review; automated checks only establish bounded format/digest consistency. Rejected/deleted content is cleared. Put any parent instructions in **Mensagem pública ao responsável**. Internal correction reasons are never copied automatically. Open **análise interna** to save **Nome para acesso** and verify documents.
5. Academic staff saves the class and optional confidential assessment, then confirms placement. Finance receives the request and a simulated payment intent. Once that simulation succeeds, save a fictional payment reference and confirm the simulated payment. IT then receives only the minimum identity section; it does not receive admissions files or the academic assessment.
6. Provisioning deliberately fails on its first attempt. The ticket stays at access creation and cannot close. IT chooses **Tentar novamente**; the same durable intent succeeds on its second attempt. Complete the request to enqueue the simulated notification. Command receipts and per-event outbox keys prevent duplicate business effects. No money moves and no accounts or messages are provisioned outside this database.

Aurora receives an independent configuration and families; its operator assigns local staff profiles before walking through internal department work. The global parent identity never carries a guardian relationship or a draft from one school to the other.

## Authorization and projection

`Enrollment` exposes allowlisted submitted fields, a coarse public status, explicitly published text and the guardian's authorized application documents. It never returns internal history, reasons, assessments, staff IDs, outbox data or staff presence. Generic request get/list/search projections deny the `parent` membership role. Guardian mutation rights require both a current verified local link and the template's explicit role/scope/stage policy; a department rule cannot bypass that family check. File authorization independently checks relationship, section/field and current local membership.

Each command, refresh, download and retry reauthorizes within the tenant transaction. Permission changes use the exclusive organization authorization gate, so queued commands cannot act after revocation commits. Parent invalidations go only to the linked user's organization-bound topic and contain no record data. Periodic 30-second reconciliation covers missed invalidations. Session/organization revocation and route changes discard protected forms. Unsaved form conflicts retain the draft and require an explicit discard/review before fresh revision commands.

The generic `workflow_department` scope binds a role to a fixed symbolic department. Optional transition `department_binding` transfers assignment atomically. Existing definitions without these additions retain their behavior. Guardian scope does not create users, grants or relationships when imported or published.

## Private file lifecycle and limits

Objects use random opaque keys; all storage rows have tenant RLS and composite ticket ownership constraints. Contents are PostgreSQL bytea, never a public directory, object URL or caller-selected path. The upload API accepts bytes, not filesystem paths. Each claim is rechecked against the same ticket, section, field and organization when saved and when required by a transition. Ready state is server-owned and cannot be supplied in form values.

Accepted declarations: PDF with header/EOF and blocked active-content markers, PNG header/end marker, JPEG start/end markers. Names and sizes are bounded; digest equality is rechecked at release. These checks are deliberately limited: they are not a comprehensive parser, malware scanner, or document-authenticity verification. Staff release is a separate manual gate. Use synthetic files only.

Twenty quarantined/ready files per ticket and 5 MiB per object bound the demo. Expiry is 30 days after upload, is checked on reads/guards, and is not reset by staff release. The existing active-tenant delivery poll clears expired contents; rejected/deleted bytes are cleared immediately. Metadata and attributable organization audit events remain. Suspended tenants are not polled; expired objects still fail authorization after reactivation and are then purged. Backups retain their own snapshots: production needs an operator-owned backup/retention policy.

Downloads return an authenticated attachment with `private, no-store`, `nosniff`, a sandbox CSP and `application/octet-stream`. Quarantined, rejected, deleted, expired, wrong-school or unrelated-family objects return not-found. Browser MIME/filename claims never establish readiness. There are no public or reusable signed download links. Required missing/unready/expired files fail verification, including after a replacement or deletion.

## Verification and remaining limits

Context tests exercise correction through completion, multiple guardians, unverified/expired/reused invitations, family IDs/counts/files, shared-account school isolation, document claim forgery, format/size/quarantine/rejection/deletion/expiry and simulation failure/retry. LiveView/HTTP tests exercise upload, form persistence, draft reset, staff controls, live revocation and authenticated response headers. Independent non-owner database connections verify RLS, composite ownership, competing guardian saves and revocation before a queued mutation.

Mobile browser checks use a 390×844 viewport with no horizontal overflow and persisted fictional values after reload. Browser file-upload/failure/retry coverage is provided by LiveView tests and backend integration tests; no exhaustive physical-device, accessibility, load or real-malware certification is claimed. Real student deployment, directory references, guardian disputes and production security/retention readiness remain outside this demonstration.
