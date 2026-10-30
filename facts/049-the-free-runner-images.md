# 049. The free GitHub-hosted runner images for the probes and scenarios

## Measured

2026-10-30, the probes workflow (run 41137356489, and the pull request run
41138261939) and the scenarios workflow (run 41137353062). The probes
workflow ran each Unix probe, the Windows probes and the kit with no agent
installed. Its step "Image" printed `uname -srm`, the OS name and the path
of `ps`, `pgrep`, `lsof`, `tmux`, `sudo` and `python3`. The scenarios
workflow ran `scenarios/first-run.sh` for 18 agents (facts 29, 30 and 46)
and `scenarios/windows-installs.ps1` for 15 agents (fact 47).

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04,
ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm, ubuntu-slim,
macos-15, macos-26, macos-15-intel, macos-26-intel, windows-2022,
windows-2025 and windows-11-arm.

## What was measured

1. Each label started a job, and each probe passed its section check on
   each label.
2. The images:

   | Label | OS | Kernel | CPU | `tmux` | `lsof` |
   |---|---|---|---|---|---|
   | ubuntu-22.04 | Ubuntu 22.04.5 LTS | 6.8.0-1070-azure | x86_64 | yes | yes |
   | ubuntu-22.04-arm | Ubuntu 22.04.5 LTS | 6.8.0-1070-azure | aarch64 | yes | yes |
   | ubuntu-24.04 | Ubuntu 24.04.5 LTS | 7.0.0-1017-azure | x86_64 | yes | yes |
   | ubuntu-24.04-arm | Ubuntu 24.04.5 LTS | 7.0.0-1017-azure | aarch64 | yes | yes |
   | ubuntu-26.04 | Ubuntu 26.04.1 LTS | 7.0.0-1017-azure | x86_64 | yes | yes |
   | ubuntu-26.04-arm | Ubuntu 26.04.1 LTS | 7.0.0-1017-azure | aarch64 | yes | yes |
   | ubuntu-slim | Ubuntu 24.04.5 LTS | 6.1.158.2-microsoft-standard | x86_64 | no | no |
   | macos-15 | macOS 15.8.2 (24H232) | Darwin 24.6.0 | arm64 | no | yes |
   | macos-15-intel | macOS 15.7.9 (24G830) | Darwin 24.6.0 | x86_64 | no | yes |
   | macos-26 | macOS 26.6.2 (25G83) | Darwin 25.6.0 | arm64 | no | yes |
   | macos-26-intel | macOS 26.6.1 (25G76) | Darwin 25.6.0 | x86_64 | no | yes |
   | windows-2022 | Windows NT 10.0.20348 | | x64 | | |
   | windows-2025 | Windows NT 10.0.26100 | | x64 | | |
   | windows-11-arm | Windows NT 10.0.26200 | | arm64 | | |

   `sudo`, `ps`, `pgrep` and `python3` were present on each Linux and macOS
   image, also on ubuntu-slim.
3. On ubuntu-slim, all seven Unix probes passed with no `lsof` and no
   `tmux`. On Linux, the probes read open files from `/proc`.
4. Each of the 18 agents installed and started on each of the ten Linux and
   macOS labels, with the same version on each label. Each agent showed the
   same first prompt on each label, with one exception: on
   ubuntu-26.04-arm, Aider first asked "Allow collection of anonymous
   analytics to help improve aider? (Y)es/(N)o [Yes]:", and did not make
   `.aider/caches/versioncheck`. On the other nine labels it first asked
   "No git repo found, create one to track aider's changes
   (recommended)?" (as in fact 30).
5. Aider: `pipx install aider-chat` worked on ubuntu-22.04 and ubuntu-24.04
   (both CPU types). It failed on ubuntu-26.04 (both CPU types) and on the
   four macOS labels with "Fatal error from uv prevented installation". On
   macos-15, the failed build of `tiktoken` ran in a `python3.15` folder.
   `uv tool install --python 3.12 aider-chat` then installed Aider 0.86.2
   on each of these labels.
6. The jobs took 3.8 to 5.6 minutes on Linux, 5.8 to 11.1 minutes on macOS
   (the Intel images were the slowest) and 3.4 to 7.0 minutes on Windows,
   for 8 to 10 agents in one job.
7. The scrub (`tools/scrub.sh`, `tools/scrub.ps1`) reads each run of four
   numbers with dots as an IPv4 address. It changed the ubuntu-slim kernel
   version in the probe header to `os: linux <ip>-microsoft-standard`, and
   the four-part file version of `claude.exe` on Windows to `<ip>`.
   `scenarios/windows-installs.ps1` now prints the four parts with spaces
   (run 41138908257).

## Mechanism

The free images differ in the tools that a scenario needs. A scenario that
needs `tmux` must install it on macOS. A probe that needs `lsof` on Linux
fails on ubuntu-slim, so the Linux probes use `/proc`.

Aider asked the analytics question on one label only, with the same
version and the same install. The choice is probably random for each new
install. The source of Aider was not read.

The Python of the newer images is too new for some Python agents. A fixed
Python (3.12 through uv) makes the install the same on each image.

## Incident

None.

## Screens

None.

## Not measured

- The number of CPUs and the memory of each image.
- The Python version of each image, except the `python3.15` folder on
  macos-15.
- The scenarios on ubuntu-slim: the workflow does not run them there.
- The images with more CPUs (`-large`, `-xlarge`), the preview images, and
  macos-14.
- Whether the first screens stay the same on these images with a login.
