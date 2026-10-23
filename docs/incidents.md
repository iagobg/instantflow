# Confidential incidents — synthetic demonstration

**Historical Sprint 06 walkthrough.** Sprint 11 D-32 retired the dedicated
Ocorrências route and Incidents context. Open the configured process in
**Processos** and its generated record page; declared views provide urgency
filtering. Files now use explicit document policies with an independent reviewer:
the uploader cannot review their own file. The following description records
the original screen behavior. See the [current checkpoint](sprint11-retirement-checkpoint.md)
for replacement and preservation evidence.

Open **Ocorrências** for the restricted urgency dashboard and **Solicitações** for section editing. All people, reports, attachments and communications must be fictional. This system does not guarantee emergency response.

## Demo roles and walkthrough

Run the forward migration with mix ecto.migrate -r Instantflow.OperatorRepo, then the normal demo seeds with mix run priv/repo/seeds.exs and the existing DEMO_PASSWORD environment variable. Both schools receive independent incident definitions. Horizonte uses docente@escola.example as reporter, direcao@escola.example as dean, and orientacao@escola.example as counselor. Aurora uses admin@escola.example as reporter and gestao@aurora.example as dean/counselor with independent local grants. Overlapping roles never imply access to support notes without named assignment.

1. As the teacher, choose **Registrar ocorrência fictícia**, fill factual description, fictional student reference, instant with timezone, location and textual urgency, save and register the incident. The draft/report is visible to its reporter and the locally authorized dean; other reporters and unassigned counselors cannot discover it.
2. As dean, open the incident, select an eligible named counselor in **Atribuir: Acompanhamento confidencial**, and give a reason. Only active local members with the configured counselor role and fixed support department appear. The assignment changes a ticket revision; after other edits use **Atualizar mantendo rascunhos** and acknowledge the current review before assigning.
3. Save the disciplinary triage, then **Concluir triagem**. Dean edits triage/actions/resolution; the assigned counselor independently edits support notes. Neither section grants access to the other. Teacher sees only the factual report and coarse current stage, without disciplinary text, assignment reasons, private notes, delivery details or confidential presence.
4. The counselor may upload a fictional PDF/PNG/JPEG of at most 5 MiB into the support attachment field. Upload enters quarantine; manually release or reject after checking the fictional content. Save the section to persist its object reference. Download, metadata, quarantine review and deletion all independently recheck section permission. The dean and other counselors cannot release or download this file. The existing private-file limits and retention apply; this is not malware scanning.
5. Dean saves a resolution plus a deliberately curated public message and fictional contact reference. **Registrar comunicação simulada** creates one durable simulated notification; it contains no automatically copied support notes. The first attempt fails. Choose **Tentar novamente**, wait for successful simulation, then close. No external message is sent, and parents receive no incident-record endpoint or internal projection.
6. Reassign or revoke the counselor with a reason. Current assignment plus current role/department grants govern every read and write. Revocation is allowed even after closure; new assignments are limited to configured triage/followup stages. Losing access clears private live drafts and files and removes the record from that counselor's dashboard. The previous/new local membership IDs and reason remain in manager-only assignment history.

## Confidentiality and collaboration

The generic assigned_user actor scope references an explicitly configured section assignment key. Section assignment configuration declares fixed target role/department, manager actors and assignment stages. It carries no operational membership in JSON exports; imported templates must resolve local role/department bindings and cannot create assignments or grants. Typed editor changes preserve the specification; the advanced JSON editor configures it.

Assignment commands use the exclusive tenant authorization gate. Ordinary reads/saves take the shared gate, so a revocation committed ahead of a queued mutation causes that mutation to fail. Assignment, attributable audit event, revision, retry receipt and durable refresh intent commit together. Distinct section saves do not conflict merely because another section changed; same-section conflicts retain only the authorized losing draft until comparison/reapply. No administration bypass exists for support content.

Dashboard counts, urgency labels and stage filters derive only from currently readable reports in the active school, with up to 100 displayed rows. Urgency is spelled out, announced through a polite atomic status region and never relies on color. Generic table/board projections omit unreadable fields; history filters confidential saves/reasons and corresponding delivery intents. Presence resolves both viewers' and editors' current local rights before showing names. Assignment refreshes are data-free, with durable ticket invalidation and 30-second reconciliation for missed events. Private file bytes never enter the static tree or event payloads.

Tests cover unrelated reporters, dean/counselor boundaries, other counselors, parents, shared-school identities, snapshots/summaries/history, typed authoring/interchange, closure failure/retry, private upload/quarantine/download/revocation, two-tab private drafts, independent section writes on real non-owner connections and deterministic revocation/save ordering. See the Sprint 06 evidence. Physical-device, exhaustive accessibility and production incident-handling certification are outside this proof of concept.
