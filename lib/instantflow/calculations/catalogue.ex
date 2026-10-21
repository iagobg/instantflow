defmodule Instantflow.Calculations.Catalogue do
  @moduledoc "Immutable local scripts; separate author, reviewer, binder, execution and source permissions."
  import Ecto.Query
  alias Instantflow.{Access, Repo, Tenant}
  alias Instantflow.Calculations.{Contract, Review, Script}
  alias Instantflow.WorkflowCatalog.Interchange

  def permit!(actor, role) do
    unless Access.role?(actor, [role]), do: Repo.rollback(:forbidden)
  end

  def register(actor, attrs) do
    Tenant.transaction(actor, fn a ->
      permit!(a, "python_author")

      valid =
        is_map(attrs) and
          Enum.sort(Map.keys(attrs)) ==
            ~w(allowed_roles fixtures input_schema key output_schema runtime source) and
          Contract.key?(attrs["key"]) and is_binary(attrs["source"]) and
          byte_size(attrs["source"]) in 1..32_768 and
          String.valid?(attrs["source"]) and Contract.digest?(attrs["runtime"]) and
          Contract.schema?(attrs["input_schema"]) and Contract.schema?(attrs["output_schema"]) and
          is_list(attrs["allowed_roles"]) and attrs["allowed_roles"] != [] and
          Enum.all?(attrs["allowed_roles"], &(&1 in Access.binding_roles() and &1 != "parent")) and
          is_list(attrs["fixtures"]) and length(attrs["fixtures"]) in 1..5 and
          Enum.all?(attrs["fixtures"], fn f ->
            is_map(f) and Enum.sort(Map.keys(f)) == ~w(input output) and
              Contract.values?(attrs["input_schema"], f["input"]) and
              Contract.values?(attrs["output_schema"], f["output"])
          end)

      unless valid, do: Repo.rollback(:invalid_script)

      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended('calculation-catalogue:' || $1::text, 0))",
        [to_string(a.organization_id)]
      )

      digest = Interchange.digest(attrs)

      if Repo.aggregate(Script, :count) >= 100 and
           not Repo.exists?(
             from s in Script, where: s.key == ^attrs["key"] and s.digest == ^digest
           ),
         do: Repo.rollback(:queue_full)

      script =
        Repo.get_by(Script, key: attrs["key"], digest: digest) ||
          Repo.insert!(%Script{
            organization_id: a.organization_id,
            key: attrs["key"],
            digest: digest,
            source: attrs["source"],
            runtime: attrs["runtime"],
            input_schema: attrs["input_schema"],
            output_schema: attrs["output_schema"],
            fixtures: attrs["fixtures"],
            allowed_roles: attrs["allowed_roles"],
            author_id: a.user_id
          })

      unless Repo.get_by(Review, script_id: script.id),
        do: Repo.insert!(%Review{organization_id: a.organization_id, script_id: script.id})

      audit!(a, "script_registered", script.id)
      Map.take(script, [:id, :key, :digest, :runtime])
    end)
  end

  # Fixture calls occur strictly outside the transaction. Revalidate reviewer authority at commit.
  def verify(actor, id) do
    with {:ok, {script, generation}} <-
           Tenant.transaction(actor, fn a ->
             permit!(a, "python_reviewer")
             {script!(id), Instantflow.Calculations.switch!()}
           end),
         true <-
           Enum.all?(script.fixtures, fn fixture ->
             request =
               Instantflow.Calculations.Runner.request(
                 script,
                 fixture["input"],
                 "fixture:" <> Ecto.UUID.generate(),
                 Ecto.UUID.generate()
               )

             case Instantflow.Calculations.Runner.execute(request) do
               {:ok, %{"status" => "succeeded", "output" => output} = response} ->
                 Instantflow.Calculations.Runner.identity?(request, response) and
                   output == fixture["output"] and Contract.values?(script.output_schema, output)

               _ ->
                 false
             end
           end) do
      Tenant.transaction(actor, fn a ->
        permit!(a, "python_reviewer")

        unless Instantflow.Calculations.switch!() == generation,
          do: Repo.rollback(:execution_disabled)

        review = review!(id)
        Repo.update!(Ecto.Changeset.change(review, verified: true, reviewer_id: a.user_id))
        audit!(a, "script_fixtures_verified", id)
        :verified
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :fixture_failed}
    end
  end

  def activate(actor, id, enabled) when is_boolean(enabled) do
    Tenant.authorize_change(actor, fn a ->
      permit!(a, "python_reviewer")
      review = review!(id)
      if enabled and not review.verified, do: Repo.rollback(:fixture_failed)

      Repo.update!(
        Ecto.Changeset.change(review,
          enabled: enabled,
          generation: review.generation + 1,
          reviewer_id: a.user_id
        )
      )

      audit!(a, if(enabled, do: "script_activated", else: "script_disabled"), id)
      :ok
    end)
  end

  def list(actor) do
    Tenant.transaction(actor, fn a ->
      unless Access.role?(a, ~w(python_author python_reviewer python_binder python_source)),
        do: Repo.rollback(:forbidden)

      Repo.all(
        from s in Script,
          join: r in Review,
          on: r.script_id == s.id,
          order_by: [desc: s.id],
          limit: 100,
          select: %{
            id: s.id,
            key: s.key,
            digest: s.digest,
            runtime: s.runtime,
            enabled: r.enabled,
            verified: r.verified
          }
      )
    end)
  end

  def source(actor, id) do
    Tenant.transaction(actor, fn a ->
      permit!(a, "python_source")
      script!(id)
    end)
  end

  def resolve!(spec) do
    script =
      Repo.get_by(Script, key: spec["script"], digest: spec["digest"]) ||
        Repo.rollback(:invalid_calculation)

    review = review!(script.id)
    unless review.enabled and review.verified, do: Repo.rollback(:invalid_calculation)
    {script, review}
  end

  def validate_bindings!(actor, d) do
    specs = for t <- d["transitions"], t["calculation"], do: t["calculation"]
    if specs != [], do: permit!(actor, "python_binder")

    Enum.each(specs, fn s ->
      {script, _} = resolve!(s)

      unless Enum.sort(Map.keys(s["inputs"])) == Enum.sort(Map.keys(script.input_schema)) and
               Enum.sort(Map.keys(s["outputs"])) == Enum.sort(Map.keys(script.output_schema)),
             do: Repo.rollback(:invalid_calculation)

      fields = Instantflow.WorkflowCatalog.Definition.fields(d)

      Enum.each(s["outputs"], fn {key, ref} ->
        if fields[ref]["type"] == "money" and script.output_schema[key]["min"] < 0,
          do: Repo.rollback(:invalid_calculation)
      end)
    end)
  end

  def script!(id), do: Repo.get(Script, id) || Repo.rollback(:not_found)

  def review!(id),
    do:
      Repo.one(from r in Review, where: r.script_id == ^id, lock: "FOR SHARE") ||
        Repo.rollback(:not_found)

  def audit!(a, operation, id),
    do:
      Repo.insert!(%Instantflow.Organizations.Event{
        organization_id: a.organization_id,
        actor_id: a.user_id,
        operation: operation,
        key: "#{operation}:#{id}:#{Ecto.UUID.generate()}"
      })
end
