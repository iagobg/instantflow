defmodule Instantflow.ReadContextTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Identity, Tenant}
  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.WorkflowCatalog.Workspaces

  test "session and navigation compose with one fresh authorization load" do
    f = workflow_fixture()
    token = Identity.create_session(f.requester.user)
    forged = %{f.requester | role: "admin", active: false}
    expected = Workspaces.navigation(f.requester)

    {{:ok, {fresh, navigation}}, report} =
      QueryProbe.capture(fn ->
        Identity.read_session(token, forged, fn context ->
          {Tenant.context_scope!(context), Workspaces.navigation_in_context(context)}
        end)
      end)

    assert fresh.role == "staff"
    assert fresh.active
    assert fresh.user == f.requester.user
    assert navigation == expected
    # User, membership, grants and the current session; no second scope load.
    assert report.groups.authorization.statements == 4
  end

  test "cached reads belong only to one callback and never accept a membership as authority" do
    f = workflow_fixture()
    value = make_ref()

    context =
      Tenant.read_context(f.requester, fn context ->
        assert Tenant.context_fetch!(context, :sample, fn _ -> value end) == value

        assert Tenant.context_fetch!(context, :sample, fn _ -> flunk("duplicate read") end) ==
                 value

        context
      end)

    assert_raise ArgumentError, fn -> Workspaces.navigation_in_context(context) end
    assert_raise ArgumentError, fn -> Tenant.context_scope!(f.requester) end

    Tenant.read_context(f.requester, fn next ->
      assert_raise ArgumentError, fn -> Tenant.context_scope!(context) end
      assert Tenant.context_fetch!(next, :sample, fn _ -> :new_read end) == :new_read
    end)
  end

  test "another process or repository cannot use the context" do
    f = workflow_fixture()
    supervisor = start_supervised!(Task.Supervisor)

    Tenant.read_context(f.requester, fn context ->
      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          assert_raise ArgumentError, fn -> Tenant.context_scope!(context) end
        end)

      Task.await(task)
      repo = Repo.get_dynamic_repo()

      try do
        Repo.put_dynamic_repo(:other_repository)
        assert_raise ArgumentError, fn -> Tenant.context_scope!(context) end
      after
        Repo.put_dynamic_repo(repo)
      end

      assert Tenant.context_scope!(context).id == f.requester.id
    end)
  end

  test "nested read contexts expire independently and reject mutation entry points" do
    f = workflow_fixture()

    Tenant.read_context(f.requester, fn outer ->
      inner = Tenant.read_context(f.requester, & &1)
      assert_raise ArgumentError, fn -> Tenant.context_scope!(inner) end
      assert Tenant.context_scope!(outer).id == f.requester.id

      for mutate <- [
            fn -> Tenant.transaction(f.requester, fn _ -> :unexpected end) end,
            fn -> Tenant.authorize_change(f.requester, fn _ -> :unexpected end) end,
            fn -> Tenant.raw(f.requester.organization_id, fn -> :unexpected end) end
          ] do
        assert_raise ArgumentError, ~r/Mutation entry points/, mutate
      end
    end)

    assert {:ok, :ok} = Tenant.transaction(f.requester, fn _ -> :ok end)
  end

  @tag :read_lock
  test "ordinary read boundaries also reject implicit write upgrades" do
    f = workflow_fixture()

    Tenant.read(f.requester, fn _ ->
      for mutate <- [
            fn -> Tenant.transaction(f.requester, fn _ -> :unexpected end) end,
            fn -> Tenant.authorize_change(f.requester, fn _ -> :unexpected end) end,
            fn -> Tenant.raw(f.requester.organization_id, fn -> :unexpected end) end
          ] do
        assert_raise ArgumentError, ~r/Mutation entry points/, mutate
      end
    end)

    assert {:ok, :ok} =
             Tenant.transaction(f.requester, fn _ ->
               assert Tenant.read(f.requester, & &1.id) == f.requester.id
               assert {:ok, :ok} = Tenant.transaction(f.requester, fn _ -> :ok end)
               :ok
             end)
  end

  @tag :read_lock
  test "ordinary read errors restore the mutation boundary" do
    f = workflow_fixture()

    assert_raise RuntimeError, "interrupted read", fn ->
      Tenant.read(f.requester, fn _ -> raise "interrupted read" end)
    end

    assert :denied == Tenant.read(f.requester, fn _ -> Repo.rollback(:test) end, :denied)

    assert_raise ArgumentError, ~r/Read locks require/, fn ->
      Tenant.lock_for_read(Instantflow.Identity.User)
    end

    assert {:ok, :ok} = Tenant.transaction(f.requester, fn _ -> :ok end)
  end

  test "exceptions and rollbacks discard context and allow later commands" do
    f = workflow_fixture()
    owner = self()

    assert_raise RuntimeError, "interrupted read", fn ->
      Tenant.read_context(f.requester, fn context ->
        send(owner, {:context, context})
        raise "interrupted read"
      end)
    end

    assert_receive {:context, failed}
    assert_raise ArgumentError, fn -> Tenant.context_scope!(failed) end

    assert :rolled_back ==
             Tenant.read_context(
               f.requester,
               fn context ->
                 send(owner, {:context, context})
                 Repo.rollback(:test)
               end,
               :rolled_back
             )

    assert_receive {:context, rolled_back}
    assert_raise ArgumentError, fn -> Tenant.context_scope!(rolled_back) end
    assert is_integer(create_ticket(f))
  end

  test "session validation rejects mismatched, expired and deleted tokens and revoked members" do
    f = workflow_fixture()
    token = Identity.create_session(f.requester.user)
    read = fn scope -> Identity.read_session(token, scope, fn _ -> :visible end) end
    assert {:error, :forbidden} = read.(f.reviewer)
    assert {:ok, :visible} = read.(f.requester)

    Repo.update_all(Instantflow.Identity.Session, set: [expires_at: ~U[2000-01-01 00:00:00Z]])
    assert {:error, :forbidden} = read.(f.requester)

    token = Identity.create_session(f.requester.user)
    Identity.delete_session(token)
    assert {:error, :forbidden} = Identity.read_session(token, f.requester, fn _ -> flunk() end)

    token = Identity.create_session(f.requester.user)
    assert {:ok, _} = Identity.revoke(f.admin, f.requester.id)
    assert {:error, :forbidden} = Identity.read_session(token, f.requester, fn _ -> flunk() end)
  end
end
