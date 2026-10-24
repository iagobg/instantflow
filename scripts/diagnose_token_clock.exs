# Test-environment diagnostics only. Trace numeric age inputs/results, never
# tokens, payloads, signatures, salts, credentials or verification secrets.
# MIX_ENV=test mix run --no-start scripts/diagnose_token_clock.exs test FILE --seed N
# MIX_ENV=test mix run --no-start scripts/diagnose_token_clock.exs precommit --seed N
unless Mix.env() == :test, do: raise("Run token-clock diagnostics only with MIX_ENV=test")
[task | arguments] = System.argv()
unless task in ["test", "precommit"], do: raise("Expected test or precommit")
Code.ensure_loaded!(Plug.Crypto)

tracer =
  spawn(fn ->
    loop = fn loop, samples, failures, largest ->
      receive do
        {:trace, pid, :call, {Plug.Crypto, :validate_age, [signed, age]}}
        when is_integer(signed) and is_integer(age) ->
          Process.put(:age_checks, Process.get(:age_checks, 0) + 1)
          loop.(loop, Map.put(samples, pid, %{signed: signed}), failures, largest)

        {:trace, pid, :return_from, {Plug.Crypto, :now_ms, 0}, now} when is_integer(now) ->
          loop.(
            loop,
            Map.update(samples, pid, %{now: now}, &Map.put(&1, :now, now)),
            failures,
            largest
          )

        {:trace, pid, :return_from, {Plug.Crypto, :validate_age, 2}, {:error, :invalid}} ->
          delta =
            case Map.get(samples, pid) do
              %{signed: signed, now: now} -> signed - now
              _ -> nil
            end

          IO.puts(:stderr, "TOKEN_CLOCK_INVALID signed_minus_now_ms=#{inspect(delta)}")
          loop.(loop, Map.delete(samples, pid), failures + 1, max(largest, delta || 0))

        {:trace, pid, :return_from, {Plug.Crypto, :validate_age, 2}, _} ->
          loop.(loop, Map.delete(samples, pid), failures, largest)

        {:summary, caller} ->
          send(caller, {:token_clock_summary, failures, largest, Process.get(:age_checks, 0)})

        _ ->
          loop.(loop, samples, failures, largest)
      end
    end

    loop.(loop, %{}, 0, 0)
  end)

for mfa <- [{Plug.Crypto, :validate_age, 2}, {Plug.Crypto, :now_ms, 0}] do
  :erlang.trace_pattern(mfa, [{:_, [], [{:return_trace}]}], [:local])
end

:erlang.trace(:all, true, [:call, {:tracer, tracer}])

try do
  Mix.Task.run(task, arguments)
after
  :erlang.trace(:all, false, [:call])

  for mfa <- [{Plug.Crypto, :validate_age, 2}, {Plug.Crypto, :now_ms, 0}] do
    :erlang.trace_pattern(mfa, false, [:local])
  end

  marker = :erlang.trace_delivered(:all)

  receive do
    {:trace_delivered, :all, ^marker} -> :ok
  after
    5000 -> :ok
  end

  send(tracer, {:summary, self()})

  receive do
    {:token_clock_summary, failures, largest, checks} ->
      IO.puts(
        :stderr,
        "TOKEN_CLOCK_SUMMARY age_checks=#{checks} invalid_age_results=#{failures} largest_future_delta_ms=#{largest}"
      )
  after
    5000 -> IO.puts(:stderr, "TOKEN_CLOCK_SUMMARY unavailable")
  end
end
