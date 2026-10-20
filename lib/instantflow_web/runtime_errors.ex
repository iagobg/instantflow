defmodule InstantflowWeb.RuntimeErrors do
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
