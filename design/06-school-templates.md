# School demonstration templates

[Design index](index.md)

These four workflows demonstrate a general-purpose platform through one coherent domain. They exercise reusable approval, routing, confidentiality, external-participation, and financial capabilities. School-specific labels and records belong to these templates and their domain modules; other organizations configure workflows appropriate to their own operations.

Displayed labels are PT-BR and configurable. Each template has authorized correction/rejection/cancellation paths with reasons where appropriate.

Install these as independent organization-owned copies. Students, guardians, permissions, accounts, configuration, and operational records never transfer with a template. A second fictional school must demonstrate separate customization and budgets; the same named department or shared user account must not link their records.

## Matrícula de estudantes

**Rascunho → Verificação de documentos → Análise acadêmica → Confirmação do pagamento → Criação de acesso → Concluída**.

Parent/admissions submits student, guardian, year/class, and documents. Admissions verifies ready attachments or requests correction. Academic staff records placement. Finance records successful simulated deposit. IT completes simulated provisioning before closure.

Views: incoming-class table, Kanban, scoped pending counts. IT receives minimum identity data. Demo: Parent A corrects a document, finance records “Pagamento simulado”, and IT sees eligible work; Parent B cannot discover it. Provisioning failure leaves the record pending with retry status.

## Aprovação de passeios

**Proposta → Análise pedagógica → Aprovação financeira → Organização do transporte → Análise de segurança → Aprovado**.

Teacher supplies itinerary, dates, destination, participants, estimated cost, and safety details. Department head approves academic value; finance reserves budget; operations records transport; authorized administration signs off safety.

Views: table, Kanban, calendar distinguishing proposed/approved trips. Changing dates, destination, participants, or cost after approval requires relevant renewed review. A principal may assign an authorized operator to unblock work without bypassing finance.

Detailed per-student consent and provider integrations are deferred unless requested.

## Registro de ocorrências

**Registrada → Triagem → Acompanhamento → Comunicação aos responsáveis → Encerrada**.

Teacher records factual description, students, time/location, and urgency. Dean triages and assigns counselor. Dean edits disciplinary actions while counselor independently edits restricted support notes. Closure requires resolution and recorded simulated communication outcome.

Views: restricted triage with urgency/assignment filters. No unrestricted incident leaderboard. Parents receive curated communication by default, not incident-record access. Demo verifies simultaneous work and that teacher/history/events cannot reveal private notes.

This demonstrates triage; it is not a guaranteed emergency alert service.

## Requisição de materiais e bens

**Solicitada → Aprovação da área → Análise orçamentária → Compra → Recebimento → Concluída**.

Teacher supplies lines, quantities, justification, amount, department. Head approves; finance reserves funds; purchasing records simulated order; receiving records deliveries. Partial delivery stays at “Recebimento”; complete delivery enables closure. Price increases beyond reservation return to approval.

Proposed accounting, pending D-07:

- Available = allocated − active reservations − committed spend.
- Finance approval reserves atomically; order confirmation converts reservation to committed spend without double subtraction.
- Pre-order cancellation releases once. Post-order cancellation requires explicit reversal/credit.
- Allocation/reversal permissions are distinct and audited.
- Trips and requisitions may share accounts; protection applies across templates.

Views: table, Kanban, authorized live budgets. Demo: two individually affordable but jointly unaffordable requests race; only one reserves, and permitted viewers converge on the same balance.

## Reuse gate

Templates pass the same validator as editor/imported definitions. Generic LiveViews cannot hardcode school stage names. Registered finance/support capabilities supply domain behavior chosen by templates.
