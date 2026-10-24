# Windows / WSL clock remediation — 2026-10-24

The selected route is one time authority: Windows Time synchronizes the host with
its existing time.windows.com peer, and Hyper-V implicit synchronization supplies
that time to WSL. Ubuntu's competing systemd-timesyncd service is disabled.

This follows [Canonical's Ubuntu-on-WSL guidance](https://ubuntu.com/wsl/docs/stable/explanation/time-sync/),
which specifically recommends disabling systemd-timesyncd on Ubuntu 24.04 when
using implicit host synchronization. Disabling Hyper-V implicit sync is not the
preferred route: Canonical documents limitations in doing so on modern WSL.
No application token checks were weakened, and the kernel clocksource stayed tsc.

## Applied configuration

The user authorized fixing the conflict. Windows required administrator elevation;
the elevated command completed after Windows' normal UAC prompt. Its existing NTP
peer was retained. The commands were:

~~~powershell
Set-Service -Name W32Time -StartupType Automatic
Start-Service -Name W32Time
w32tm.exe /resync /rediscover
~~~

Windows Time now reports Running with Automatic startup. Resynchronization returned
success, with time.windows.com,0x9 as its source and a successful synchronization
record. The existing host vmictimesync service was not changed.

A normal sudo attempt required a password. Automatic approval review then rejected
using WSL's root interface without specific authorization for that elevation route.
The user explicitly approved the exact command, which was subsequently applied:

~~~powershell
wsl.exe -d Ubuntu -u root --exec systemctl disable --now systemd-timesyncd.service
~~~

Verified WSL state: ActiveState=inactive, SubState=dead, UnitFileState=disabled.
The Hyper-V live timesync_implicit parameter remains Y. Linux reports NTP=no,
which refers to its local NTP service; Hyper-V host synchronization is still active.
No WSL restart, kernel parameter, clocksource, registry time-source or timezone
change was performed. Existing application processes and database data were retained.

## Before and after

Before remediation, simultaneous Windows/WSL samples found two guest backward
reads in 60 seconds and a largest wall/monotonic interval discrepancy of 546.898 ms;
the host had no backward reads. See [the original verification](demo-clock-verification.md).

Two consecutive 60-second guest samples completed with zero backward reads and
zero interval discrepancies above 50 ms:

| Window | Samples | Backward reads | Largest interval discrepancy |
|---|---:|---:|---:|
| WSL 1 | 30,001 | 0 | 86 μs |
| WSL 2 | 29,963 | 0 | 8 μs |
| Windows, simultaneous with WSL 1 | 3,806 | 0 | 1.8793 ms |

Both guest preflight runs exited 0. The second window overlapped regression tests,
so the measurements include application-test load. Compared with two backward
reads and a 546.898 ms discrepancy in the pre-fix guest sample, the observed
instability disappeared after the configuration change.

The previously affected tests passed: 28 tests, zero failures (seed 865528), with
417 token-age checks and zero invalid results. Full instrumented mix precommit passed 377 tests with zero failures (seed 865528;
161.0 seconds), with 1194 token-age checks, zero invalid results and largest future
delta 0 ms. Existing migration module-redefinition warnings were unchanged.
Git diff --check passed. Compact evidence is retained in
[clock-remediation.txt](evidence/demo-readiness/clock-remediation.txt).

The demonstrated clock-conflict blocker is remediated and verified in the current
running environment. This conclusion combines an applied configuration change,
consecutive clean clock samples and the affected/full test suites, rather than
relying on passing test reruns alone. It does not claim that suspend/resume or
restart behavior was exercised.

Five post-fix guest UTC readings bracketed by Windows timestamps all yielded
intervals containing zero offset, unlike the uniformly positive bounds before:

| Round trip | Guest-minus-host lower bound | Upper bound |
|---:|---:|---:|
| 113 ms | -37 ms | +76 ms |
| 104 ms | -37 ms | +67 ms |
| 116 ms | -37 ms | +79 ms |
| 127 ms | -40 ms | +87 ms |
| 99 ms | -36 ms | +63 ms |

The bridge is too slow to infer a precise submillisecond host/guest offset. These
bounds show no measurable positive offset outside bridge uncertainty after the fix.
The independent in-guest clock samples provide the higher-resolution stability
measurement. Host service startup and guest NTP were changed together, so this is
verification of the selected configuration as a whole, not isolation of each
individual contributor.

## Rollback and operational limits

The prior guest state was enabled/active. An authorized operator can restore it:

~~~powershell
wsl.exe -d Ubuntu -u root --exec systemctl enable --now systemd-timesyncd.service
~~~

The prior Windows Time state was Manual/Stopped. In an administrator PowerShell,
restoring that exact state would use Set-Service -Name W32Time -StartupType Manual
and Stop-Service -Name W32Time. These rollback commands were not executed because
they would restore the conflicting prior configuration.

The changes persist as service configuration, but suspend/resume and a Windows or
WSL restart were not forced during this task. Check the service states and rerun
elixir scripts/check_demo_clock.exs 60 after the next normal resume/restart. A clean
observation interval cannot guarantee that every future host clock correction
will be monotonic. The fix addresses the demonstrated duplicate-sync configuration;
normal operational clock checks remain useful.
