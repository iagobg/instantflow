defmodule InstantflowWeb.RuntimeErrors do
  def message(:retired_invitation),
    do: "Este convite antigo foi descontinuado. Solicite um novo convite de participante."

  def message(:retired_version),
    do:
      "Esta versão histórica está arquivada. Crie um processo com os contratos atuais para continuar."

  def message(:unsupported_contract),
    do: "Configure e publique o contrato operacional antes de iniciar atendimentos."

  def message(:execution_disabled), do: "Os cálculos Python estão desativados pelo operador."

  def message(:calculation_required),
    do: "Aguarde um cálculo válido para os dados atuais antes de avançar."

  def message(:invalid_calculation),
    do: "Revise o cálculo, os mapeamentos e as permissões locais."

  def message(:invalid_script),
    do: "Informe código, esquemas inteiros, versão do executor e exemplos sintéticos válidos."

  def message(:fixture_failed),
    do: "Os exemplos sintéticos não passaram. Revise o código e a disponibilidade do executor."

  def message(:invalid_assignee),
    do: "Escolha uma pessoa ativa com o perfil e departamento locais exigidos."

  def message(:ineligible_participant),
    do: "Escolha outra pessoa ativa com um dos papéis elegíveis deste relacionamento."

  def message(:invalid_reference),
    do:
      "A referência deixou de estar disponível. Atualize e escolha um relacionamento verificado deste registro."

  def message(:account_exists), do: "Já existe uma conta com este nome neste departamento."

  def message(:insufficient_budget), do: "Saldo insuficiente para reservar este valor."

  def message(:invalid_budget),
    do:
      "Orçamento indisponível nesta organização. Peça à administração para revisar o mapeamento local; registros existentes mantêm a conta da sua publicação."

  def message(:invalid_amount), do: "Informe um valor positivo em centavos."

  def message(:renew_finance_review),
    do: "Revise a proposta e renove as aprovações antes de alterar o custo."

  def message(:explicit_reversal_required),
    do: "O pedido já foi confirmado; registre um estorno explícito."

  def message(:invalid_delivery),
    do: "Informe uma quantidade recebida entre zero e o total solicitado."

  def message(:incomplete_delivery),
    do: "A quantidade total recebida deve corresponder à quantidade solicitada."

  def message(:invalid_finance_state),
    do: "A situação financeira foi alterada. Atualize e revise a solicitação."

  def message(:attachment_not_ready),
    do: "O documento obrigatório ainda não foi liberado pela equipe autorizada."

  def message(:invalid_attachment),
    do: "Documento indisponível para este formulário e esta organização."

  def message(:invalid_file), do: "Envie um PDF, PNG ou JPEG fictício de até 5 MB."

  def message(:quota),
    do: "Limite de documentos deste registro atingido. Exclua um documento antes de reenviar."

  def message(:invalid_state), do: "O documento já foi revisado ou expirou. Atualize a página."

  def message(:queue_full),
    do:
      "A fila desta organização atingiu o limite. Aguarde as entregas pendentes antes de tentar novamente."

  def message(:conflict),
    do:
      "Esta solicitação foi atualizada. Seu rascunho foi preservado. Revise os dados antes de tentar novamente."

  def message(:required_fields),
    do: "Preencha e salve todos os campos obrigatórios antes de avançar."

  def message(:reason_required), do: "Informe o motivo para realizar esta ação."

  def message(:guard_failed),
    do: "As condições para avançar ainda não foram atendidas. Confira as entregas simuladas."

  def message(:forbidden), do: "Você não tem permissão para realizar esta ação nesta etapa."

  def message(:idempotency_mismatch),
    do: "Este comando já foi usado com outros dados. Atualize a página antes de tentar novamente."

  def message({:invalid_values, errors}), do: Enum.join(errors, " ")
  def message(_), do: "Não foi possível concluir a ação. Revise os dados e tente novamente."
end
