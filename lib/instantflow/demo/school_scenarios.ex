defmodule Instantflow.Demo.SchoolScenarios do
  @moduledoc false
  import Instantflow.Demo.Scenario
  alias Instantflow.{Identity, Participants, PrivateDocuments, WorkflowRuntime}
  alias Instantflow.Identity.Department

  def install!(operator, org, departments, presenter, author, purchasing_bindings, password) do
    extra_departments =
      Map.new([{"admissions", "Secretaria"}, {"it", "TI"}, {"support", "Orientação"}], fn {key,
                                                                                           name} ->
        {key <> "_department",
         ensure(operator, Department, [organization_id: org.id, name: name], %{}).id}
      end)

    departments = Map.merge(departments, extra_departments)

    registrar =
      actor!(
        operator,
        org,
        departments,
        presenter,
        password,
        "secretaria",
        "Lia Souza — secretaria",
        "admissions",
        "admissions"
      )

    it =
      actor!(
        operator,
        org,
        departments,
        presenter,
        password,
        "ti",
        "Davi Alves — acesso simulado",
        "it",
        "it"
      )

    dean =
      actor!(
        operator,
        org,
        departments,
        presenter,
        password,
        "direcao",
        "Rita Costa — direção",
        "safety",
        "dean"
      )

    counselor =
      actor!(
        operator,
        org,
        departments,
        presenter,
        password,
        "orientacao",
        "Nina Rocha — orientação",
        "support",
        "counselor"
      )

    family =
      member!(
        operator,
        org,
        departments["admissions_department"],
        "familia@escola.example",
        "Família fictícia Oliveira",
        "external",
        password
      )

    grant!(presenter, presenter, departments["admissions_department"], "admissions")
    grant!(presenter, presenter, departments["it_department"], "it")
    presenter = Identity.scope(presenter.user_id, org.id)

    enrollment = enrollment!(presenter, registrar, it, family, departments)
    trip = trips!(presenter, author, dean, purchasing_bindings)
    incident = incidents!(presenter, author, dean, counselor, departments)
    {[enrollment, trip, incident], [presenter, registrar, it, dean, counselor, family]}
  end

  defp actor!(operator, org, departments, admin, password, prefix, name, department, role) do
    member =
      member!(
        operator,
        org,
        departments[department <> "_department"],
        prefix <> "@escola.example",
        name,
        "staff",
        password
      )

    grant!(admin, member, departments[department <> "_department"], role)
    Identity.scope(member.user_id, org.id)
  end

  defp enrollment!(presenter, registrar, it, family, departments) do
    original = Instantflow.Examples.definition("enrollment")

    definition =
      Map.update!(original, "views", fn views ->
        Enum.map(views, fn view ->
          if view["key"] == "board",
            do:
              Map.put(view, "columns", [
                "stage",
                "application.student_name",
                "application.school_year"
              ]),
            else: view
        end)
      end)

    version =
      version!(
        presenter,
        "enrollment",
        %{
          "roles" => %{
            "guardian" => ["external"],
            "admissions" => ["admissions"],
            "academic" => ["head"],
            "finance" => ["finance"],
            "it" => ["it"]
          },
          "departments" => %{
            "admissions_department" => departments["admissions_department"],
            "academic_department" => departments["head_department"],
            "finance_department" => departments["finance_department"],
            "it_department" => departments["it_department"]
          }
        },
        definition: definition,
        upgrade_from: original
      )

    targets =
      ~w(draft draft documents documents correction academic academic payment payment provisioning provisioning complete)

    Enum.with_index(targets, 1)
    |> Enum.each(fn {target, index} ->
      key = "demo:d01:enrollment:1:v#{version.id}:case#{index}"

      case!(registrar, version, key, fn id ->
        link!(registrar, family, id, key)

        document =
          ok!(
            PrivateDocuments.upload(
              family,
              id,
              "application",
              "document",
              "matricula-ficticia-#{index}.pdf",
              "%PDF-1.4\nDocumento fictício sem dados reais\n%%EOF",
              key <> ":upload"
            )
          )

        save!(
          family,
          id,
          "application",
          %{
            "student_name" =>
              "Estudante fictício #{String.pad_leading(to_string(index), 2, "0")}",
            "guardian_name" => "Família fictícia Oliveira",
            "school_year" => "6º ano",
            "document" => document.object_key
          },
          key <> ":application"
        )

        if target != "draft" do
          transition!(family, id, "submit", key <> ":submit")

          if target == "correction" do
            transition!(
              registrar,
              id,
              "correct",
              key <> ":correct",
              "Conferir o ano escolar no documento fictício."
            )
          else
            if target != "documents" do
              ok!(PrivateDocuments.review(registrar, document.object_key, true, key <> ":review"))

              save!(
                registrar,
                id,
                "identity",
                %{"display_name" => "Estudante fictício #{index}"},
                key <> ":identity"
              )

              transition!(registrar, id, "verify", key <> ":verify")

              if target != "academic" do
                save!(
                  presenter,
                  id,
                  "placement",
                  %{
                    "class" => "6A",
                    "assessment" => "Avaliação interna fictícia; não compartilhar com a família."
                  },
                  key <> ":placement"
                )

                transition!(presenter, id, "place", key <> ":place")
                delivery!(presenter, id, "simulate_payment", false)

                if target != "payment" do
                  save!(
                    presenter,
                    id,
                    "payment",
                    %{"reference" => "PAGAMENTO-SIMULADO-#{index}"},
                    key <> ":payment"
                  )

                  transition!(presenter, id, "paid", key <> ":paid")
                  delivery!(it, id, "simulate_provisioning", target == "complete")

                  if target == "complete" do
                    transition!(it, id, "finish", key <> ":finish")
                    delivery!(it, id, "simulate_notification", false)
                  end
                end
              end
            end
          end
        end
      end)
    end)

    version
  end

  defp link!(actor, family, id, key) do
    command = %{
      "operation" => "create",
      "ticket_id" => id,
      "membership_id" => family.id,
      "relationship" => "family",
      "expected_revision" => 0,
      "key" => key <> ":link"
    }

    result = ok!(Participants.command(actor, command))

    ok!(
      Participants.command(actor, %{
        command
        | "operation" => "verify",
          "expected_revision" => result["revision"],
          "key" => key <> ":verify-family"
      })
    )
  end

  defp trips!(presenter, author, dean, bindings) do
    version = version!(presenter, "field_trip", bindings)

    destinations = [
      "Jardim botânico fictício",
      "Museu de ciências fictício",
      "Parque das nascentes fictício",
      "Observatório fictício",
      "Biblioteca municipal fictícia",
      "Centro cultural fictício"
    ]

    Enum.zip(destinations, ~w(draft academic finance purchase safety complete))
    |> Enum.with_index(1)
    |> Enum.each(fn {{destination, target}, index} ->
      key = "demo:d01:field_trip:1:v#{version.id}:case#{index}"

      case!(author, version, key, fn id ->
        save!(
          author,
          id,
          "request",
          %{
            "summary" => "Visita pedagógica: #{destination}",
            "justification" => "Atividade fictícia de observação e registro em grupo.",
            "quantity" => 20 + index,
            "amount" => 12000 + index * 1000,
            "date" => "2026-11-#{11 + index}",
            "destination" => destination,
            "itinerary" => "Saída às 09h; retorno às 16h. Transporte simulado.",
            "risks" => "Acompanhamento por docentes; contatos e autorizações fictícios."
          },
          key <> ":request"
        )

        if target != "draft" do
          transition!(author, id, "submit", key <> ":submit")

          if target != "academic" do
            transition!(presenter, id, "academic_approve", key <> ":academic")

            if target != "finance" do
              transition!(presenter, id, "reserve", key <> ":reserve")

              if target != "purchase" do
                save!(
                  presenter,
                  id,
                  "order",
                  %{"reference" => "TRANSPORTE-SIMULADO-#{index}"},
                  key <> ":transport"
                )

                transition!(presenter, id, "order", key <> ":order")

                if target == "complete" do
                  save!(dean, id, "safety", %{"confirmed" => true}, key <> ":safety")
                  transition!(dean, id, "approve", key <> ":approve")
                end
              end
            end
          end
        end
      end)
    end)

    version
  end

  defp incidents!(presenter, author, dean, counselor, departments) do
    version =
      version!(presenter, "incident", %{
        "roles" => %{"teacher" => ["teacher"], "dean" => ["dean"], "counselor" => ["counselor"]},
        "departments" => %{
          "dean_department" => departments["safety_department"],
          "support_department" => departments["support_department"]
        }
      })

    Enum.with_index(~w(triage followup closed), 1)
    |> Enum.each(fn {target, index} ->
      key = "demo:d01:incident:1:v#{version.id}:case#{index}"

      case!(author, version, key, fn id ->
        save!(
          author,
          id,
          "report",
          %{
            "facts" => "Exercício fictício #{index}: desentendimento durante atividade em grupo.",
            "students" => "Personagens fictícios A e B",
            "occurred_at" => "2026-10-21T12:00:00Z",
            "location" => "Pátio fictício",
            "urgency" => Enum.at(["Rotina", "Prioritária", "Urgente"], index - 1)
          },
          key <> ":report"
        )

        transition!(author, id, "submit", key <> ":submit")

        if target != "triage" do
          data = ok!(WorkflowRuntime.get(dean, id))

          ok!(
            WorkflowRuntime.command(dean, %{
              "operation" => "assign",
              "ticket_id" => id,
              "section" => "support",
              "membership_id" => counselor.id,
              "expected_revision" => data.ticket.revision,
              "reason" => "Acompanhamento fictício pela orientação.",
              "key" => key <> ":assign"
            })
          )

          save!(
            dean,
            id,
            "discipline",
            %{"triage" => "Escuta inicial fictícia realizada."},
            key <> ":triage-values"
          )

          transition!(dean, id, "triage", key <> ":triage")

          save!(
            counselor,
            id,
            "support",
            %{
              "notes" =>
                "Nota privada fictícia #{index}: plano de acompanhamento individual. Não divulgar."
            },
            key <> ":private-notes"
          )

          if target == "closed" do
            save!(
              dean,
              id,
              "discipline",
              %{"resolution" => "Mediação fictícia concluída."},
              key <> ":resolution"
            )

            save!(
              dean,
              id,
              "communication",
              %{
                "recipient" => "Responsável fictício",
                "message" =>
                  "Atividade de mediação concluída; acompanhamento combinado. Mensagem simulada."
              },
              key <> ":communication"
            )

            transition!(dean, id, "communicate", key <> ":communicate")
            delivery!(dean, id, "simulate_notification", true)
            transition!(dean, id, "close", key <> ":close")
          end
        end
      end)
    end)

    version
  end
end
