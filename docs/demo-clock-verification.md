# Windows / WSL clock verification — 2026-10-24

Read-only verification confirms an unstable WSL guest clock while the Windows host
clock remained stable during the same observation window. The configuration also
matches a documented conflict between Hyper-V implicit time synchronization and
an active NTP client in Ubuntu. This is a strong candidate for the configuration
cause; a controlled change-and-restore experiment was not performed, so the exact
mechanism remains unproven. No application, token-validation or OS settings changed.

## Direct observations

| Check | Windows host | Ubuntu WSL guest |
|---|---|---|
| Platform | Windows 11 Pro 10.0.26200; WSL reports Windows build 26200.9711 | WSL 3.0.3.0; kernel 6.18.54.1-microsoft-standard-WSL2; Ubuntu 24.04.4 LTS |
| Sampling duration | 60.009 seconds | 60 seconds |
| Samples | 3,807 | 29,944 |
| Backward wall-clock reads | 0 | 2 |
| Wall/monotonic discrepancies above 50 ms | 0 | 2 |
| Largest wall/monotonic interval discrepancy | 3.05 ms | 546.898 ms |

Windows was sampled using DateTimeOffset.UtcNow against Stopwatch; WSL used the
checked-in Elixir preflight with System.os_time against System.monotonic_time.
Samples ran concurrently with the test reruns. The WSL preflight exited 1. This
measurement describes the observation window, not an indefinite guarantee for the
host or a test of either machine's accuracy relative to an external UTC standard.

Five additional guest UTC readings were bracketed by Windows UTC timestamps.
The measured guest-minus-host bounds, including bridge latency, were:

| Round trip | Lower bound | Upper bound |
|---:|---:|---:|
| 124 ms | +61 ms | +185 ms |
| 116 ms | +66 ms | +182 ms |
| 107 ms | +67 ms | +174 ms |
| 109 ms | +70 ms | +179 ms |
| 114 ms | +72 ms | +186 ms |

All five bounds placed the guest clock ahead of the host. WSL's own journal also
records prior 'Time jumped backwards' events from systemd-journald. These are
independent of Phoenix session creation and verification.

## Configuration and source attribution

The running Hyper-V module parameter timesync_implicit is Y, and the kernel command
line includes hv_utils.timesync_implicit=1. Ubuntu's systemd-timesyncd is enabled
and running, with a WSL-specific unit drop-in that explicitly allows it to run.
It contacts ntp.ubuntu.com on a 32-second poll interval. The observed status showed
an offset of -504.084 ms, delay 207.389 ms, jitter 8.689 ms and frequency +26.061 ppm.
NTP synchronization being reported as active did not prevent backward reads.

Windows W32Time and vmictimesync were both stopped with Manual startup. The Windows
NTP client is enabled and configured for time.windows.com,0x9; querying w32tm status
returned 'The service has not been started.' W32Time also has service triggers.
Stopped service status alone does not establish a Windows configuration defect,
and vmictimesync is a guest integration service rather than proof of the host's
own time discipline. No user .wslconfig override was present.

The current Linux clocksource is tsc. Available alternatives include Hyper-V
clocksource implementations, but this investigation does not establish TSC as the
cause and did not switch clocksources.

Canonical's [official Ubuntu-on-WSL time synchronization documentation](https://ubuntu.com/wsl/docs/stable/explanation/time-sync/)
explains that modern WSL implicitly synchronizes the guest to the Windows host.
It warns that an additional NTP client can conflict with host synchronization,
and specifically recommends disabling systemd-timesyncd on Ubuntu 24.04 and older
when relying on implicit host sync. The observed configuration matches that warning.
This is vendor guidance plus local configuration evidence, not a local causal A/B
result. The [Microsoft WSL issue tracker](https://github.com/microsoft/WSL/issues/11790)
also contains reports of repeated backward jumps, but other users' reports do not
prove this machine's exact cause.

## Tests and readiness

The previously affected field-surface tests and builder tests passed: 28 tests,
zero failures (seed 865528; 16.4 seconds), with 417 token-age checks and zero invalid
results. Full instrumented mix precommit then passed 377 tests with zero failures
(seed 865528; 162.2 seconds), with 1194 token-age checks, zero invalid results and
largest future delta 0 ms. Test database VMs ran serially. Existing migration
module-redefinition warnings remain unchanged. Git diff --check passed.
Compact results are retained in [clock-verification.txt](evidence/demo-readiness/clock-verification.txt).

The clock gate remains open even if a regression rerun passes. The next controlled
operator investigation would compare the same clock sample with only one time
synchronization authority active, restoring the prior state afterward. Windows
host time correctness should be checked before making its clock authoritative.
This verification did not stop services, change startup modes, resynchronize time,
restart WSL, edit system configuration or weaken token timestamp checks.
