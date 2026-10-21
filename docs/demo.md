# Integrated synthetic demonstration

This is a proof of concept for configured workflow collaboration. Use fictional people, documents, amounts and contact references. All payment, order, provisioning and communication effects are explicitly simulated.

## Prepare and choose a school

Follow the README setup with the pinned runtime and PostgreSQL. Run forward migrations and demo seeds; the same supplied DEMO_PASSWORD applies to newly created fictional accounts and existing passwords remain unchanged. Seeds can be repeated. Choose Escola Horizonte or Escola Aurora at **Trocar organização**. The global admin@escola.example identity administers Horizonte and is a requester in Aurora; gestao@aurora.example administers Aurora. A role or private relationship in one school grants nothing in the other.

Keep separate browser profiles/sessions for different fictional people. Keep separate tabs for the two schools. The organization in each route is authoritative, and switching with an unsaved request asks before discarding that tab's draft.

## Four workflows

| Workflow | Primary path | Observable failure/recovery | Detailed walkthrough |
|---|---|---|---|
| Matrícula | Parent A submits; admissions verifies; coordination places; finance confirms simulation; IT provisions | Quarantine blocks verification; first provisioning fails and requires retry; Parent B cannot open the record or file | [Enrollment](enrollment.md) |
| Requisição | Teacher submits; coordination approves; finance reserves; operations orders and receives | Shared funds cannot over-reserve; partial receiving cannot finish; pre-order release differs from explicit post-order reversal | [Finance](finance.md) |
| Passeio | Teacher proposes; coordination reviews; finance reserves; operations records transport; direction confirms safety | Proposal changes restart approvals; missing transport/safety cannot be skipped; final approval posts funds | [Finance](finance.md) |
| Ocorrência | Teacher reports; direction triages and assigns; counselor writes private notes; direction resolves and curates communication | Dean cannot read support notes; unassigned counselor cannot discover the report; failed simulated notification blocks closure until retry | [Incidents](incidents.md) |

Horizonte roles are docente, secretaria, coordenacao, financeiro, operacoes, ti, direcao and orientacao at @escola.example. Parent accounts are responsavel.a@escola.example and responsavel.b@escola.example. The administrator has allocation permission; direction has a separate reversal profile. Inspect current profile/department grants in **Equipe e convites** rather than assuming administration bypasses record rules.

## Create and import a fifth workflow

As the Horizonte administrator, open **Modelos de fluxo**, create a unique key such as space_request and name it **Reserva de espaço fictícia**. The starter contains a Resumo field and a conclusion by another authorized person. Map Solicitante to Professor, Responsável to Coordenação, and Departamento responsável to the local Coordenação department; review and publish. A teacher creates and saves a request; a different coordination user concludes it.

Review the explicit JSON export, download it and import a new independent copy with a distinct key. The import is an unpublished draft with unresolved local mappings. Resolve them, review and publish explicitly. Export contains structure and symbols only, never requests, funds, student records, counselor notes, users or active assignments.

In Aurora, its administrator can import the definition independently and change its name/labels. Map only Aurora departments/accounts/profiles. Verify Horizonte's published name and existing pinned requests remain unchanged. The shared Horizonte administrator's Aurora staff membership must not author or export there. [Authoring and interchange](template-editor.md), [PT-BR authoring guide](../design/workflow_authoring_guide.pt-BR.md).

## Automated integrated walkthrough and recovery

~~~sh
mix precommit
mix assets.build
# Needs seeded local synthetic demo and PostgreSQL client tools on PATH or PG_BIN:
mix run --no-start scripts/rehearse_delivery.exs
# Separate legacy migration/rollback refusal gate:
python3 scripts/rehearse_01a.py
~~~

The delivery rehearsal reads the serving demo only to create a private base dump, restores it into a new generated source database, and performs all four full workflows plus authored/imported fifth-workflow copies through guarded runtime-role APIs. It proves partial-delivery/closure gates, payment replay, simulated retry, unrelated-parent denial, local customization and foreign mapping rejection. It then backs up populated private files, financial holds/entries, named assignments, events, receipts and outbox records, restores into another generated database, compares every row digest/count, verifies real private download under the runtime role and refuses destructive rollback without changing data.

Generated databases and backups remain for inspection; no serving database is reset, overwritten or deleted. Reports are under ignored .local; committed [delivery evidence](evidence/sprint07-recovery.json) contains aggregate counts/digests and outcome flags, never private content or credentials. This is whole-database recovery, not tenant-selective recovery or a production cutover.
