# Changelog

## [0.9.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.8.0...corpus-v0.9.0) (2026-10-31)


### Features

* add facts 066 to 069 from the probe kit on macOS and Ubuntu ([#53](https://github.com/xSAVIKx/agent-signals/issues/53)) ([6b0a86d](https://github.com/xSAVIKx/agent-signals/commit/6b0a86de152de4286cb30cbdb2bc4198a10ac387))
* add facts 070 to 072 from the probe kit on Windows ([#55](https://github.com/xSAVIKx/agent-signals/issues/55)) ([ed1ea21](https://github.com/xSAVIKx/agent-signals/commit/ed1ea218791edbf4bd1b7d4e062c8bc559ef8270))
* **probes:** add one-line starts of the kit for macOS, Linux and Windows ([#51](https://github.com/xSAVIKx/agent-signals/issues/51)) ([71a2470](https://github.com/xSAVIKx/agent-signals/commit/71a24701049d150b58021a79ed5fa84b2a77fccd))
* **probes:** attach the probe kit to each corpus release and download it in the one-liners ([#56](https://github.com/xSAVIKx/agent-signals/issues/56)) ([2b79a8e](https://github.com/xSAVIKx/agent-signals/commit/2b79a8e4ea2544d7514d12acea16a3d1c23d85ce))
* **probes:** print procStart of each Claude pid file with the start time from ps, sysctl and /proc ([#58](https://github.com/xSAVIKx/agent-signals/issues/58)) ([af68e66](https://github.com/xSAVIKx/agent-signals/commit/af68e66e1c649bbbd4c58c5181dfe2dbd7976048))
* **site:** add llms.txt, JSON indexes and Markdown copies for agents ([#47](https://github.com/xSAVIKx/agent-signals/issues/47)) ([6b91c06](https://github.com/xSAVIKx/agent-signals/commit/6b91c06f90504c8b8ea2c22939ebf6c81f5fa383))
* **site:** add Markdown, Claude and ChatGPT actions to each page ([#49](https://github.com/xSAVIKx/agent-signals/issues/49)) ([0b98b0a](https://github.com/xSAVIKx/agent-signals/commit/0b98b0a1953f9d4db863349e7d2b5cc62538decc))


### Bug Fixes

* **probes:** accept agent as a name of Cursor and refuse unknown agents in a guided step ([#54](https://github.com/xSAVIKx/agent-signals/issues/54)) ([b6a1997](https://github.com/xSAVIKx/agent-signals/commit/b6a1997a9eb6b16f010d1ba24795e3cef1ed618a))
* **probes:** hide Windows project paths, keys and names in the probe output ([#59](https://github.com/xSAVIKx/agent-signals/issues/59)) ([75d05ca](https://github.com/xSAVIKx/agent-signals/commit/75d05ca4a9adb5e7385fc66b47363dd46045ecfe))
* **probes:** keep probe variables out of the helpers, and fix two macOS checks ([#52](https://github.com/xSAVIKx/agent-signals/issues/52)) ([8ff5cbe](https://github.com/xSAVIKx/agent-signals/commit/8ff5cbe682eadddbbaaf2e2b05b5b3a22fa8d1c5))

## [0.8.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.7.0...corpus-v0.8.0) (2026-10-31)


### Features

* **site:** add a releases page and keep the corpus release as Latest ([#43](https://github.com/xSAVIKx/agent-signals/issues/43)) ([5e716c7](https://github.com/xSAVIKx/agent-signals/commit/5e716c7ac807a3fab604cb48582c642136bced4e))


### Bug Fixes

* **site:** keep tables and the navigation inside the screen, and put who and how first in the README ([#45](https://github.com/xSAVIKx/agent-signals/issues/45)) ([420ed0b](https://github.com/xSAVIKx/agent-signals/commit/420ed0b93a941b1a3e73748a1c8a8cb42ffb94b3))

## [0.7.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.6.0...corpus-v0.7.0) (2026-10-31)


### Features

* add 14 agents, a CODEX_HOME run and more Windows agents to the first-run CI ([#41](https://github.com/xSAVIKx/agent-signals/issues/41)) ([f0637e8](https://github.com/xSAVIKx/agent-signals/commit/f0637e8b2ebf7b5812e9db40b19e6b16ebb30bf6))
* **python:** add a Python library that loads the corpus ([#39](https://github.com/xSAVIKx/agent-signals/issues/39)) ([e655ac3](https://github.com/xSAVIKx/agent-signals/commit/e655ac378443f814e2bdfea4ad3a028028901dc2))

## [0.6.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.5.0...corpus-v0.6.0) (2026-10-31)


### Features

* add a ConPTY driver and a first-run scenario for Windows ([#37](https://github.com/xSAVIKx/agent-signals/issues/37)) ([5452c4b](https://github.com/xSAVIKx/agent-signals/commit/5452c4b261d778ce16b2bb3e597a744981fbdb2c))
* add the first screens of 16 more agents with no login ([#34](https://github.com/xSAVIKx/agent-signals/issues/34)) ([cf0649d](https://github.com/xSAVIKx/agent-signals/commit/cf0649d77573c58c052cea25db102d57ab1557a6))

## [0.5.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.4.0...corpus-v0.5.0) (2026-10-30)


### Features

* add Codex scenarios for a denial, interrupts, hooks and the daemon ([#30](https://github.com/xSAVIKx/agent-signals/issues/30)) ([7b6440e](https://github.com/xSAVIKx/agent-signals/commit/7b6440e690b8aeedbe294f0c8cc54545627194b3))
* add facts 031 to 035, more Claude Code waits and a resume ([#27](https://github.com/xSAVIKx/agent-signals/issues/27)) ([ca5740d](https://github.com/xSAVIKx/agent-signals/commit/ca5740d9a06ea49fac27bd4bd5d5c74686f46b9e))
* add the documentation website ([#28](https://github.com/xSAVIKx/agent-signals/issues/28)) ([3aa17bb](https://github.com/xSAVIKx/agent-signals/commit/3aa17bba1199a6774381de2fe73fc5312816310d))
* measure more agy 1.4.7 signals (facts 041 to 045) ([#26](https://github.com/xSAVIKx/agent-signals/issues/26)) ([5922f5a](https://github.com/xSAVIKx/agent-signals/commit/5922f5aa527bf72b8532b3f16aac503e4aebccf4))
* run the probes and scenarios on each free runner image, with facts 046 to 050 ([#25](https://github.com/xSAVIKx/agent-signals/issues/25)) ([793ee1b](https://github.com/xSAVIKx/agent-signals/commit/793ee1b7f7e3069fd6eb9f703afba2f845b37ddb))


### Bug Fixes

* keep version numbers out of the IP rule of the scrub ([#33](https://github.com/xSAVIKx/agent-signals/issues/33)) ([94fa3f5](https://github.com/xSAVIKx/agent-signals/commit/94fa3f5e8322cf7ebfa9cb5be9980325b2090316))

## [0.4.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.3.0...corpus-v0.4.0) (2026-10-30)


### Features

* add fact 030, the first start of four more agents ([#22](https://github.com/xSAVIKx/agent-signals/issues/22)) ([78bff0c](https://github.com/xSAVIKx/agent-signals/commit/78bff0c8277aa2fd560249ce923dc762f4a38b80))
* add the Copilot CLI and Gemini CLI probes for Linux and macOS ([#24](https://github.com/xSAVIKx/agent-signals/issues/24)) ([be4d524](https://github.com/xSAVIKx/agent-signals/commit/be4d524df1a1d0229e2e0ffc67c462723fd3fc7e))

## [0.3.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.2.0...corpus-v0.3.0) (2026-10-30)


### Features

* add Codex CLI 0.164.0 screens: idle, busy and the F2 Warnings view ([#17](https://github.com/xSAVIKx/agent-signals/issues/17)) ([de64562](https://github.com/xSAVIKx/agent-signals/commit/de64562ed2dea71c29efce58e5e6b15b89855c99))
* add fact 029, the first start of each agent with no login ([#20](https://github.com/xSAVIKx/agent-signals/issues/20)) ([4035d26](https://github.com/xSAVIKx/agent-signals/commit/4035d26b9e3da68be2695905bd0b776d325e9732))
* add the agy turn scenario and its fact ([#14](https://github.com/xSAVIKx/agent-signals/issues/14)) ([fa47abe](https://github.com/xSAVIKx/agent-signals/commit/fa47abe591c95ed9c75c4aa376310e33e500b70b))
* add the Claude permission scenario and its facts ([#12](https://github.com/xSAVIKx/agent-signals/issues/12)) ([c14c386](https://github.com/xSAVIKx/agent-signals/commit/c14c386494cb142dff5336c1a7b7c4c1d3e16731))
* add the Codex approval scenarios and their facts ([#13](https://github.com/xSAVIKx/agent-signals/issues/13)) ([0d336bd](https://github.com/xSAVIKx/agent-signals/commit/0d336bd2d0dd37a79d84ce6d42c9c69d67165181))
* add the Cursor CLI macOS probe and its first facts ([#8](https://github.com/xSAVIKx/agent-signals/issues/8)) ([1e7c981](https://github.com/xSAVIKx/agent-signals/commit/1e7c9810af5ea107868fe4691218191dd4bc4946))
* add the first-run scenario and the scenarios workflow ([#19](https://github.com/xSAVIKx/agent-signals/issues/19)) ([56e15b0](https://github.com/xSAVIKx/agent-signals/commit/56e15b0e5ee705795bdb28af1079835d8b746821))
* add the probes, the kit and the scrub for Linux and macOS ([#15](https://github.com/xSAVIKx/agent-signals/issues/15)) ([bfed8ab](https://github.com/xSAVIKx/agent-signals/commit/bfed8ab699548479b7dc74d00dc42e3f6f604f21))
* add the Windows probes, the Windows kit and the PowerShell scrub ([#16](https://github.com/xSAVIKx/agent-signals/issues/16)) ([b674c03](https://github.com/xSAVIKx/agent-signals/commit/b674c0383c636c8b40139027cdef545b74d1c6d6))

## [0.2.0](https://github.com/xSAVIKx/agent-signals/compare/corpus-v0.1.0...corpus-v0.2.0) (2026-10-24)


### Features

* add Codex CLI 0.163.0 screens and facts ([#5](https://github.com/xSAVIKx/agent-signals/issues/5)) ([3f65f0c](https://github.com/xSAVIKx/agent-signals/commit/3f65f0cdb7a84f7b8c61c6b67951219f7f9ffd06))
* **go:** add a Go library that loads the corpus ([#4](https://github.com/xSAVIKx/agent-signals/issues/4)) ([b033130](https://github.com/xSAVIKx/agent-signals/commit/b03313074f9b92e174053c8a7e6b34710e1b2d7d))

## 0.1.0 (2026-10-24)


### Features

* seed the corpus with the tg-bridge screens and facts ([#1](https://github.com/xSAVIKx/agent-signals/issues/1)) ([132edd3](https://github.com/xSAVIKx/agent-signals/commit/132edd34ff7e68b7b8ff15d5c16c21d8f1f0d992))
