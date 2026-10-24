# Read-only local preflight. A passing sample is not a guarantee of clock stability.
# elixir scripts/check_demo_clock.exs [seconds, 1..60; default 10]
seconds =
  case System.argv() do
    [] ->
      10

    [raw] ->
      case Integer.parse(raw) do
        {value, ""} when value in 1..60 -> value
        _ -> raise ArgumentError, "Expected duration in seconds (1..60)"
      end

    _ ->
      raise ArgumentError, "Expected at most one duration"
  end

sample = fn -> {System.os_time(:microsecond), System.monotonic_time(:microsecond)} end
start = sample.()
{_, started} = start

loop = fn loop, {previous_wall, previous_mono}, count, backwards, steps, largest ->
  # Yield between observations; no busy loop and no changes to system time.
  receive do
  after
    1 -> :ok
  end

  {wall, mono} = current = sample.()
  wall_delta = wall - previous_wall
  discrepancy = abs(wall_delta - (mono - previous_mono))
  backwards = backwards + if(wall_delta < 0, do: 1, else: 0)
  steps = steps + if(discrepancy > 50_000, do: 1, else: 0)
  largest = max(largest, discrepancy)

  if mono - started >= seconds * 1_000_000 do
    %{
      samples: count + 1,
      backward_reads: backwards,
      steps_over_50ms: steps,
      largest_wall_monotonic_delta_us: largest,
      duration_seconds: seconds
    }
  else
    loop.(loop, current, count + 1, backwards, steps, largest)
  end
end

result = loop.(loop, start, 0, 0, 0, 0)
IO.inspect(result, label: "DEMO_CLOCK_SAMPLE")
if result.backward_reads > 0 or result.steps_over_50ms > 0, do: System.halt(1)
