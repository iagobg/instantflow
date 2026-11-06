# MIX_ENV=test mix run --no-start scripts/benchmark_cycle.exs
# Local disposable database only. No Sandbox: every write really commits.
unless Mix.env() == :test and is_nil(Process.whereis(Instantflow.Supervisor)),
  do: raise("Run with MIX_ENV=test mix run --no-start in a fresh VM")

ExUnit.start(autorun: false, seed: 0, max_cases: 1)

defmodule Instantflow.CycleBenchmark do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Instantflow.{Delivery, Identity, OperatorRepo, Repo, WorkflowCatalog, WorkflowFixtures}
  alias Instantflow.Diagnostics.{ConnectionProbe, QueryProbe}
  alias Instantflow.Collaboration.Presence
  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.WorkflowRuntime.{Section, Ticket}
  @endpoint InstantflowWeb.Endpoint

  def run do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    unless config[:hostname] in ["localhost", "127.0.0.1"],
      do: raise("This benchmark requires a local disposable database")

    {:ok, control} = Postgrex.start_link(config ++ [database: "postgres"])
    database = "instantflow_cycle_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    try do
      {:ok, operator} = OperatorRepo.start_link(database: database, pool_size: 2)

      try do
        Ecto.Migrator.run(
          OperatorRepo,
          Application.app_dir(:instantflow, "priv/repo/migrations"),
          :up,
          all: true,
          log: false
        )

        Application.put_env(
          :instantflow,
          Repo,
          Repo.config()
          |> Keyword.delete(:url)
          |> Keyword.merge(Keyword.take(config, [:hostname, :port]))
          |> Keyword.merge(
            database: database,
            username: "instantflow_runtime",
            password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
            pool: DBConnection.ConnectionPool,
            pool_size: 4
          )
        )

        for key <- [
              :delivery_worker,
              :maintenance_worker,
              :calculation_worker,
              :calculation_execution
            ],
            do: Application.put_env(:instantflow, key, false)

        {:ok, _} = Application.ensure_all_started(:instantflow)
        Logger.configure(level: :warning)

        try do
          %{failures: 0} = ExUnit.run()
        after
          Application.stop(:instantflow)
        end
      after
        Supervisor.stop(operator)
      end
    after
      Postgrex.query!(control, "DROP DATABASE #{database} WITH (FORCE)")
      GenServer.stop(control)
    end

    path = report_path()

    report =
      path |> File.read!() |> Jason.decode!() |> Map.put("disposable_database_removed", true)

    File.write!(path, Jason.encode!(report, pretty: true) <> "\n")
    IO.puts("Full-cycle benchmark complete: #{path}")
  end

  test "committed operations converge across records and list after outbox delivery" do
    tasks = start_supervised!(Task.Supervisor)

    [["instantflow_runtime", false, false]] =
      Repo.query!(
        "SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname=current_user"
      ).rows

    [[postgres]] = Repo.query!("SHOW server_version").rows
    f = fixture()

    # Warm the HTTP route and password implementation before measuring login.
    get(build_conn(), "/entrar")
    {:ok, _} = Identity.authenticate(f.requester.user.email, "fictional-password-123")
    {_, anonymous} = measure(fn -> assert get(build_conn(), "/entrar").status == 200 end)

    logins =
      for _ <- 1..3 do
        {_, report} =
          measure(fn ->
            conn =
              post(build_conn(), "/entrar",
                login: %{email: f.requester.user.email, password: "fictional-password-123"}
              )

            assert conn.status == 302
          end)

        report
      end

    {_, concurrent_logins} =
      measure(fn ->
        tasks
        |> Task.Supervisor.async_stream_nolink(
          1..4,
          fn _ ->
            post(build_conn(), "/entrar",
              login: %{email: f.requester.user.email, password: "fictional-password-123"}
            ).status
          end,
          max_concurrency: 4,
          timeout: 30_000
        )
        |> Enum.each(fn result -> assert result == {:ok, 302} end)
      end)

    id = WorkflowFixtures.create_ticket(f)
    {:ok, _} = WorkflowFixtures.save(f.requester, id, WorkflowFixtures.values())
    drain(tasks)
    requester = login(f.requester)
    reviewer = login(f.reviewer)
    path = "/o/cycle/solicitacoes/#{id}"
    {{:ok, author, _}, mount} = measure(fn -> live(requester, path) end)
    {:ok, peer, _} = live(reviewer, path)
    {:ok, list, _} = live(reviewer, "/o/cycle/solicitacoes")
    views = [author, peer, list]
    Enum.each(views, &render/1)

    saves =
      for n <- 1..3 do
        values = Map.put(WorkflowFixtures.values(), "summary", "Synthetic revision #{n}")

        {phases, total} =
          measure(fn ->
            {_, immediate} =
              phase(fn ->
                author |> form("#section-form-request", section: values) |> render_submit()
              end)

            {_, deferred} =
              phase(fn ->
                drain(tasks)
                Enum.each(views, &render/1)
                assert_converged(id, [author, peer])

                assert OperatorRepo.get_by!(Section, ticket_id: id, key: "request").values ==
                         values

                assert has_element?(peer, "#sections", values["summary"])
              end)

            %{immediate: immediate, deferred: deferred}
          end)

        assert total.sql.statements ==
                 phases.immediate.sql.statements + phases.deferred.sql.statements

        Map.put(phases, :full_cycle, total)
      end

    # A failed side effect generates another refresh without changing ticket revision.
    {phases, transition} =
      measure(fn ->
        {_, immediate} =
          phase(fn ->
            author
            |> form("#transition-form", action: %{reason: ""})
            |> render_submit(%{"transition" => "submit"})
          end)

        {_, deferred} =
          phase(fn ->
            drain(tasks)
            Enum.each(views, &render/1)
            assert_converged(id, [author, peer])
            assert OperatorRepo.get!(Ticket, id).stage == "review"
            assert has_element?(list, "#tickets-#{id} .badge", "Em análise")
            assert has_element?(peer, "button[id^='retry-']")
          end)

        %{immediate: immediate, deferred: deferred}
      end)

    revision = OperatorRepo.get!(Ticket, id).revision

    {_, retry_report} =
      measure(fn ->
        peer |> element("button[id^='retry-']") |> render_click()
        drain(tasks)
        Enum.each(views, &render/1)
        assert_converged(id, [author, peer])
        assert OperatorRepo.get!(Ticket, id).revision == revision
        refute has_element?(peer, "button[id^='retry-']")
        assert has_element?(peer, "#transition-approve")
      end)

    # Stop connected views before the observer control; no recovery timer traffic.
    Enum.each(views, fn view -> GenServer.stop(view.pid) end)

    burst = notification_burst(f, reviewer, tasks)
    unrelated_workspace = unrelated_workspace(f, tasks)
    curated_burst = curated_burst(f, tasks)

    report = %{
      source: source(),
      environment: "Local disposable database; runtime login; committed writes; pool size 4",
      postgres: postgres,
      pool_size: 4,
      connected_views: 3,
      organization_members: 3,
      anonymous_login_page: anonymous,
      login: logins,
      four_concurrent_logins: concurrent_logins,
      record_http_and_connected_mount: mount,
      saves: saves,
      submit: Map.put(phases, :full_cycle, transition),
      retry: retry_report,
      notification_burst: burst,
      unrelated_workspace: unrelated_workspace,
      curated_burst: curated_burst,
      collaboration_matrix: collaboration_matrix(tasks),
      observer_control: overhead(),
      completion:
        "Outbox empty after bounded drains on an independent connection; dispatcher committed; all three LiveViews rendered; both record revisions match storage; delivery failure and retry visible without a new ticket revision",
      limitations:
        "Local synthetic workload, not a capacity estimate. HTTP/LiveView protocol driven in-process; no browser/network latency. Workers invoked explicitly without poll delay. Legacy scenarios exclude presence heartbeats; the collaboration matrix includes explicit heartbeat events. Recovery timers excluded. Operator-only validation queries excluded. Only the outer window traces leases; nested phase query counters add overhead. Control measures one probe pair and includes separate setup/teardown cost. Lease boundaries exclude final handoff bookkeeping."
    }

    File.mkdir_p!(Path.dirname(report_path()))
    File.write!(report_path(), Jason.encode!(report, pretty: true) <> "\n")
  end

  defp fixture(opts \\ []) do
    org =
      OperatorRepo.insert!(%Organization{
        slug: Keyword.get(opts, :slug, "cycle"),
        name: "Synthetic"
      })

    department = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Synthetic"})
    password_hash = Instantflow.Identity.Password.hash("fictional-password-123")

    [admin | members] =
      for role <- ["admin" | List.duplicate("staff", Keyword.get(opts, :users, 2))] do
        user =
          OperatorRepo.insert!(%User{
            email: "cycle-#{System.unique_integer([:positive])}@example.test",
            name: "Synthetic",
            password_hash: password_hash
          })

        OperatorRepo.insert!(%Membership{
          organization_id: org.id,
          user_id: user.id,
          department_id: department.id,
          role: role
        })

        Identity.scope(user.id, org.id)
      end

    bindings = %{
      "roles" => %{"requester" => ["admin", "staff"], "reviewer" => ["staff"]},
      "departments" => %{"review_department" => department.id}
    }

    {:ok, version} =
      WorkflowCatalog.publish(
        admin,
        Keyword.get(opts, :definition, WorkflowFixtures.definition_fixture()),
        bindings
      )

    %{
      admin: admin,
      requester: hd(members),
      reviewer: List.last(members),
      members: members,
      slug: org.slug,
      version: version
    }
  end

  defp collaboration_matrix(tasks) do
    %{
      audience: Enum.map([1, 5, 10], &audience_cycle(&1, tasks)),
      same_section: Enum.map([2, 5], &editing_race(&1, :same, tasks)),
      different_sections: editing_race(2, :different, tasks),
      completion:
        "Presence refs observed on PubSub, tracker barrier completed, then every view rendered; saves committed and outbox empty; losing same-section drafts preserved; independent-section saves both committed",
      limitations:
        "One connected record per distinct staff user, one organization per case, four runtime connections; HTTP mounts are sequential, heartbeat/save bursts use a start barrier; draft events are delivered after client debounce; no browser timing, network or polling delay. Presence follow-up SQL is included. Each connected case must finish before the 30-second reconciliation timer. Timings include assertions and observers."
    }
  end

  defp collaboration_definition do
    definition = WorkflowFixtures.definition_fixture()
    [section] = definition["sections"]

    section =
      Map.update!(section, "access", fn access ->
        Enum.map(access, &Map.put(&1, "edit_stages", ["draft"]))
      end)

    Map.put(definition, "sections", [section, Map.put(section, "key", "notes")])
  end

  defp audience_cycle(count, tasks) do
    {f, id, topic, views, mount, started} = connected_case(count, "audience-#{count}", tasks)
    [author | _] = views
    original = OperatorRepo.get_by!(Section, ticket_id: id, key: "request")

    {_, idle} =
      measure(fn ->
        parallel(tasks, views, &render_hook(&1, "heartbeat", %{}))
        Enum.each(views, &render/1)
        assert Presence.list(topic) == %{}
      end)

    drafts =
      for n <- 1..3 do
        {_, report} =
          measure(fn ->
            before = presence_refs(topic)

            author
            |> form("#section-form-request", section: %{summary: "Draft #{n}"})
            |> render_change()

            await_presence(topic, views, before)
            assert has_element?(author, "#section-form-request input[value='Draft #{n}']")
            assert OperatorRepo.get_by!(Section, ticket_id: id, key: "request") == original
          end)

        report
      end

    {_, heartbeat} =
      measure(fn ->
        before = presence_refs(topic)
        render_hook(author, "heartbeat", %{})
        await_presence(topic, views, before)
        assert has_element?(author, "#section-form-request input[value='Draft 3']")
      end)

    saves =
      for n <- 1..3 do
        values = Map.put(WorkflowFixtures.values(), "summary", "Saved #{n}")

        {_, report} =
          measure(fn ->
            author |> form("#section-form-request", section: values) |> render_submit()
            drain(tasks)
            Enum.each(views, &render/1)
            assert_converged(id, views)
            assert OperatorRepo.get_by!(Section, ticket_id: id, key: "request").values == values

            for view <- views do
              refute has_element?(view, "#conflict-request")
              assert has_element?(view, "#section-form-request input[value='Saved #{n}']")
            end
          end)

        report
      end

    close_case(topic, views, started)

    %{
      connected_users: count,
      organization_members: length(f.members) + 1,
      mounts: mount,
      idle_heartbeat_burst: idle,
      draft_events: drafts,
      recent_author_heartbeat: heartbeat,
      saves: saves
    }
  end

  defp editing_race(count, mode, tasks) do
    {_f, id, topic, views, _mount, started} =
      connected_case(count, "edit-#{mode}-#{count}", tasks)

    edits =
      views
      |> Enum.with_index()
      |> Enum.map(fn {view, index} ->
        section = if mode == :different and index == 1, do: "notes", else: "request"
        values = Map.put(WorkflowFixtures.values(), "summary", "Editor #{index}")
        {view, section, values}
      end)

    parallel(tasks, edits, fn {view, section, values} ->
      view |> form("#section-form-#{section}", section: values) |> render_change()
    end)

    await_presence(topic, views)
    before_attempts = OperatorRepo.aggregate(Instantflow.Delivery.Attempt, :count)
    before_revision = OperatorRepo.get!(Ticket, id).revision

    before_sections =
      Map.new(
        OperatorRepo.all(from s in Section, where: s.ticket_id == ^id),
        &{&1.key, &1.revision}
      )

    accepted = if mode == :same, do: 1, else: count

    {_, report} =
      measure(fn ->
        parallel(tasks, edits, fn {view, section, values} ->
          view |> form("#section-form-#{section}", section: values) |> render_submit()
        end)

        drain(tasks)
        Enum.each(views, &render/1)
        assert_converged(id, views)
        assert OperatorRepo.get!(Ticket, id).revision == before_revision + accepted

        assert OperatorRepo.aggregate(Instantflow.Delivery.Attempt, :count) ==
                 before_attempts + accepted

        outcomes =
          for {view, section, values} <- edits do
            persisted = OperatorRepo.get_by!(Section, ticket_id: id, key: section)
            assert persisted.revision == Map.fetch!(before_sections, section) + 1

            assert has_element?(
                     view,
                     "#section-form-#{section} input[value='#{values["summary"]}']"
                   )

            if persisted.values == values do
              refute has_element?(view, "#conflict-#{section}")
              :accepted
            else
              assert has_element?(view, "#conflict-#{section}")
              :conflict
            end
          end

        assert Enum.count(outcomes, &(&1 == :accepted)) == accepted
      end)

    close_case(topic, views, started)
    Map.merge(report, %{editors: count, accepted: accepted, conflicts: count - accepted})
  end

  defp connected_case(count, slug, tasks) do
    f = fixture(users: count, slug: slug, definition: collaboration_definition())
    id = WorkflowFixtures.create_ticket(f)
    drain(tasks)
    topic = Presence.topic(f.requester.organization_id, id)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, topic)
    conns = Enum.map(f.members, &login/1)
    started = System.monotonic_time(:millisecond)

    {views, mount} =
      measure(fn ->
        for conn <- conns do
          {:ok, view, _} = live(conn, "/o/#{slug}/solicitacoes/#{id}")
          assert has_element?(view, "#section-form-request")
          assert has_element?(view, "#section-form-notes")
          view
        end
      end)

    {f, id, topic, views, mount, started}
  end

  defp parallel(supervisor, items, fun) do
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(items, fn item ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          send(parent, {:ready, barrier, self()})

          receive do
            {:start, ^barrier} -> fun.(item)
          after
            5_000 -> flunk("concurrent operation start barrier timed out")
          end
        end)
      end)

    for task <- tasks do
      pid = task.pid
      assert_receive {:ready, ^barrier, ^pid}, 5_000
    end

    for task <- tasks, do: send(task.pid, {:start, barrier})
    Enum.map(tasks, &Task.await(&1, 15_000))
  end

  defp presence_refs(topic) do
    topic
    |> Presence.list()
    |> Enum.flat_map(fn {_, %{metas: metas}} -> Enum.map(metas, & &1.phx_ref) end)
    |> MapSet.new()
  end

  defp await_presence(topic, views, before \\ MapSet.new()) do
    await_refs(topic, MapSet.difference(presence_refs(topic), before), :joins)
    # Presence.list synchronizes with the tracker that sent the local broadcast.
    # Its reply proves dispatch to every subscriber finished before render barriers.
    Presence.list(topic)
    Enum.each(views, &render/1)
  end

  defp await_refs(topic, expected, kind) do
    if MapSet.size(expected) > 0 do
      assert_receive %Phoenix.Socket.Broadcast{
                       topic: ^topic,
                       event: "presence_diff",
                       payload: diff
                     },
                     5_000

      received =
        diff
        |> Map.fetch!(kind)
        |> Enum.flat_map(fn {_, %{metas: metas}} -> Enum.map(metas, & &1.phx_ref) end)
        |> MapSet.new()

      await_refs(topic, MapSet.difference(expected, received), kind)
    end
  end

  defp close_case(topic, views, started) do
    assert System.monotonic_time(:millisecond) - started < 30_000,
           "connected case overlapped the reconciliation timer"

    refs = presence_refs(topic)
    Enum.each(views, &GenServer.stop(&1.pid))
    await_refs(topic, refs, :leaves)
    assert Presence.list(topic) == %{}
    Phoenix.PubSub.unsubscribe(Instantflow.PubSub, topic)
  end

  defp notification_burst(f, conn, tasks) do
    # Twenty changed records fit in one configured dispatcher batch. Seed and
    # commit changes before measuring only delivery and the connected list work.
    ids = for _ <- 1..20, do: WorkflowFixtures.create_ticket(f)
    drain(tasks)
    {:ok, list, _} = live(conn, "/o/cycle/solicitacoes")
    render(list)

    for id <- ids do
      {:ok, _} = WorkflowFixtures.save(f.requester, id, WorkflowFixtures.values())
    end

    before_attempts = OperatorRepo.aggregate(Instantflow.Delivery.Attempt, :count)

    {_, report} =
      measure(fn ->
        drain(tasks)
        render(list)
        assert has_element?(list, "#requests-count", "21 disponíveis")

        for id <- ids do
          ticket = OperatorRepo.get!(Ticket, id)
          assert ticket.refreshed_revision == ticket.revision
        end

        assert OperatorRepo.aggregate(Instantflow.Delivery.Attempt, :count) ==
                 before_attempts + 20
      end)

    GenServer.stop(list.pid)
    Map.merge(report, %{changed_records: 20, connected_list_views: 1, window: "deferred only"})
  end

  defp unrelated_workspace(f, tasks) do
    id = WorkflowFixtures.create_ticket(f)
    drain(tasks)
    assert {:error, :not_found} = Instantflow.WorkflowRuntime.get(f.admin, id)
    {:ok, view, _} = live(login(f.admin), "/o/cycle/processos/#{f.version.workflow_id}")
    assert has_element?(view, "#process-view-navigation")
    {:ok, _} = WorkflowFixtures.save(f.requester, id, WorkflowFixtures.values())
    probe = start_supervised!({QueryProbe, owner: view.pid})

    {_, report} =
      measure(fn ->
        drain(tasks)
        render(view)
        assert has_element?(view, "#process-view-navigation")
        assert OperatorRepo.get!(Ticket, id).refreshed_revision == 2
      end)

    workspace_queries = QueryProbe.finish(probe)
    stop_supervised(QueryProbe)
    GenServer.stop(view.pid)

    Map.merge(report, %{
      workspace_queries: workspace_queries,
      window: "deferred only",
      description:
        "Core-only record; one connected process workspace; viewer cannot discover the changed record"
    })
  end

  defp login(scope),
    do: Plug.Test.init_test_session(build_conn(), user_token: Identity.create_session(scope.user))

  defp curated_burst(f, tasks) do
    user =
      OperatorRepo.insert!(%User{
        email: "curated-cycle@example.test",
        name: "Synthetic",
        password_hash: f.admin.user.password_hash
      })

    OperatorRepo.insert!(%Membership{
      organization_id: f.admin.organization_id,
      user_id: user.id,
      department_id: f.admin.department_id,
      role: "external"
    })

    recipient = Identity.scope(user.id, f.admin.organization_id)

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => f.admin.department_id}
    }

    {:ok, version} =
      WorkflowCatalog.publish(
        f.admin,
        Instantflow.CuratedFixtures.definition("success"),
        bindings
      )

    ids =
      for _ <- 1..20 do
        id = WorkflowFixtures.create_ticket(%{f | version: version})
        {:ok, _} = WorkflowFixtures.save(f.requester, id, %{"summary" => "Released snapshot"})

        for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
          {:ok, _} =
            Instantflow.Participants.command(
              f.admin,
              Instantflow.BuilderFixtures.participant_command(
                id,
                recipient.id,
                operation,
                revision
              )
            )
        end

        {:ok, data} = Instantflow.WorkflowRuntime.get(f.admin, id)

        {:ok, _} =
          Instantflow.Delivery.Curated.release(
            f.admin,
            id,
            "outcome",
            recipient.id,
            data.ticket.revision,
            Ecto.UUID.generate()
          )

        id
      end

    drain(tasks)

    {:ok, inbox, _} =
      live(login(recipient), "/o/cycle/processos/#{version.workflow_id}/comunicacoes")

    assert has_element?(inbox, "#message-count", "20 mensagem")
    assert has_element?(inbox, "#curated-inbox article dd", "Released snapshot")
    refute has_element?(inbox, "a[href*='/registros/']")

    for id <- ids do
      {:ok, _} = WorkflowFixtures.save(f.requester, id, %{"summary" => "Private revised value"})
    end

    probe = start_supervised!({QueryProbe, owner: inbox.pid})

    {_, report} =
      measure(fn ->
        drain(tasks)
        render(inbox)
        assert has_element?(inbox, "#message-count", "20 mensagem")
        assert has_element?(inbox, "#curated-inbox article dd", "Released snapshot")
        refute has_element?(inbox, "#curated-inbox article dd", "Private revised value")
        for id <- ids, do: assert_converged(id, [])
      end)

    inbox_queries = QueryProbe.finish(probe)
    stop_supervised(QueryProbe)
    GenServer.stop(inbox.pid)

    Map.merge(report, %{
      changed_records: 20,
      connected_inboxes: 1,
      inbox_queries: inbox_queries,
      window: "deferred only"
    })
  end

  defp drain(tasks) do
    Task.Supervisor.async_nolink(tasks, fn -> drain_pending(10) end) |> Task.await(30_000)
  end

  defp drain_pending(remaining) do
    if OperatorRepo.exists?(from m in Instantflow.Delivery.Message, where: m.status == "pending") do
      assert remaining > 0, "outbox did not converge"
      Delivery.drain()
      drain_pending(remaining - 1)
    end
  end

  defp assert_converged(id, views) do
    ticket = OperatorRepo.get!(Ticket, id)
    assert ticket.refreshed_revision == ticket.revision

    for view <- views do
      assert :sys.get_state(view.pid).socket.assigns.data.ticket.revision == ticket.revision
    end
  end

  defp measure(fun) do
    {{result, sql}, connections} =
      ConnectionProbe.capture(fn -> QueryProbe.capture(fun, scope: :all) end)

    assert connections.complete
    assert connections.failed_checkouts == 0
    assert sql.errors == 0
    {result, %{sql: sql, connections: connections}}
  end

  defp phase(fun) do
    {result, sql} = QueryProbe.capture(fun, scope: :all)
    assert sql.errors == 0
    {result, %{sql: sql}}
  end

  defp overhead do
    workload = fn -> Repo.checkout(fn -> for _ <- 1..50, do: Repo.query!("SELECT 1") end) end
    workload.()

    for n <- 1..10 do
      order = if rem(n, 2) == 0, do: [true, false], else: [false, true]

      Enum.reduce(order, %{}, fn enabled, acc ->
        {us, result} = :timer.tc(fn -> if enabled, do: measure(workload), else: workload.() end)

        if enabled do
          {_, report} = result
          Map.merge(acc, %{with_probes_ms: us / 1000, observed_window_ms: report.sql.elapsed_ms})
        else
          Map.put(acc, :without_probes_ms, us / 1000)
        end
      end)
    end
  end

  defp report_path, do: System.get_env("CYCLE_BENCHMARK_REPORT", ".local/cycle-benchmark.json")

  defp source do
    root = Path.expand("..", __DIR__)
    {revision, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)

    {diff, 0} =
      System.cmd(
        "git",
        ["diff", "--no-ext-diff", "HEAD", "--", "lib", "config", "priv", "mix.exs", "mix.lock"],
        cd: root
      )

    %{
      git_head: String.trim(revision),
      tracked_runtime_dirty: diff != "",
      tracked_runtime_diff_sha256: Base.encode16(:crypto.hash(:sha256, diff), case: :lower),
      harness_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(__ENV__.file)), case: :lower)
    }
  end
end

Instantflow.CycleBenchmark.run()
