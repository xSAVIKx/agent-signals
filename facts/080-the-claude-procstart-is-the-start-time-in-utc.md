# 080. The Claude `procStart` on macOS is the process start time in UTC

## Measured

2026-11-07 (UTC), Claude Code 2.1.319 installed, ten interactive processes
of 2.1.287, 2.1.288, 2.1.295, 2.1.311, 2.1.312, 2.1.316, 2.1.318 (two) and
2.1.319, on macOS 26.6.2 (arm64). The local time zone was one hour ahead of
UTC on the probe date and two hours ahead in summer time. The probe kit
(`probes/run.sh`, probe `claude/unix.sh`) printed `procStart` of each
`~/.claude/sessions/<pid>.json` and three start times of the same pid.
Measured on: real machine.

## What was measured

1. For all ten processes, `procStart` was the same string as
   `TZ=UTC ps -o lstart= -p <pid>` with the trailing spaces removed.
   Example:

   ```
   procStart: Thu Nov  5 20:20:29 2026
   ps lstart: Thu Nov  5 21:20:29 2026
   ps lstart TZ=UTC: Thu Nov  5 20:20:29 2026
   sysctl p_starttime: 1793910029.757567
   ```

2. `ps -o lstart=` with the local time zone gave a time one or two hours
   later than `procStart`. The difference was two hours for the processes
   that started in summer time and one hour for the others. So a compare
   in local time fails on macOS.
3. `ps -o lstart=` adds four spaces after the year. `procStart` has no
   trailing spaces.
4. The seconds of `p_starttime` from `sysctl kern.proc.pid.<pid>`, in UTC,
   in the form `%a %b %e %H:%M:%S %Y`, gave `procStart` for all ten
   processes. The day of the month has a space before it when it has one
   digit (`Nov  5`). The microseconds are not in `procStart`.
5. The pid file form did not change between 2.1.287 and 2.1.319.

## Mechanism

A reader on macOS can check a pid file (facts 023, 066) like this:

1. Read the start time of the pid in UTC, from `TZ=UTC ps -o lstart=` or
   from `p_starttime`.
2. Write it in the form `%a %b %e %H:%M:%S %Y`.
3. Compare it with `procStart`. Remove trailing spaces before the compare.

A match proves that the pid file belongs to the process that runs now, to
the second.

## Incident

None. Before this fact, a reader did not compare `procStart` on macOS,
because no form matched. That reader compared the time in the local time
zone.

## Screens

None.

## Not measured

- macOS on x64.
- A process that started in the same second as a stopped process with the
  same pid.
- What `procStart` holds when the user changes the time zone while the
  process runs.
