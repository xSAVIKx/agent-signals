# Changelog

## [0.17.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.16.0...go/v0.17.0) (2026-11-09)


### Features

* **scenarios:** measure Claude Code after its pipes close and the Codex app-server status ([#124](https://github.com/xSAVIKx/agent-signals/issues/124)) ([6e89c43](https://github.com/xSAVIKx/agent-signals/commit/6e89c435e77fab45b707b72cd1abeecc93fca625))

## [0.16.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.15.2...go/v0.16.0) (2026-11-08)


### Features

* **probes:** run opencode with the fake model and measure when it asks ([#122](https://github.com/xSAVIKx/agent-signals/issues/122)) ([73d90da](https://github.com/xSAVIKx/agent-signals/commit/73d90da4664e4cfd2e3a8af46e288bcd34d8f6f7))

## [0.15.2](https://github.com/xSAVIKx/agent-signals/compare/go/v0.15.1...go/v0.15.2) (2026-11-08)


### Bug Fixes

* **probes:** keep work folders out of temp folders and pass JSON args on Windows ([#120](https://github.com/xSAVIKx/agent-signals/issues/120)) ([99450ef](https://github.com/xSAVIKx/agent-signals/commit/99450ef3a5815c3eead82d560005889c2793f6b5))

## [0.15.1](https://github.com/xSAVIKx/agent-signals/compare/go/v0.15.0...go/v0.15.1) (2026-11-08)


### Bug Fixes

* **corpus:** measure fact 085 with the run folder outside the temp folders ([#118](https://github.com/xSAVIKx/agent-signals/issues/118)) ([6e219ac](https://github.com/xSAVIKx/agent-signals/commit/6e219ac7648e74a9419256c02ce5e791c00eb053))

## [0.15.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.14.0...go/v0.15.0) (2026-11-08)


### Features

* **go:** answer the review requests of the auto modes in the fake model ([#114](https://github.com/xSAVIKx/agent-signals/issues/114)) ([ba051da](https://github.com/xSAVIKx/agent-signals/commit/ba051dac57c98f6c2fd1e80bcf4f9456af0321a3))
* **probes:** record the conditions of each session step and add one step for each mode ([#116](https://github.com/xSAVIKx/agent-signals/issues/116)) ([616d5de](https://github.com/xSAVIKx/agent-signals/commit/616d5de14e0bd72c7a324849838cd2a98585da1e))

## [0.14.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.13.1...go/v0.14.0) (2026-11-08)


### Features

* **go:** add the file-write texts "Write a file" and "Write outside" to the fake model ([#112](https://github.com/xSAVIKx/agent-signals/issues/112)) ([70c2cbe](https://github.com/xSAVIKx/agent-signals/commit/70c2cbe9de9510ae6eee8fd077a5c9875c14dc27))

## [0.13.1](https://github.com/xSAVIKx/agent-signals/compare/go/v0.13.0...go/v0.13.1) (2026-11-07)


### Bug Fixes

* **probes:** fixes from the unattended runs of 0.16.0 ([#110](https://github.com/xSAVIKx/agent-signals/issues/110)) ([c3758dc](https://github.com/xSAVIKx/agent-signals/commit/c3758dce81679765ce35475634b93cb7efeba014))

## [0.13.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.12.1...go/v0.13.0) (2026-11-07)


### Features

* **go:** add the fakemodel package and the agent-signals-fake-model command ([#106](https://github.com/xSAVIKx/agent-signals/issues/106)) ([ff12c2f](https://github.com/xSAVIKx/agent-signals/commit/ff12c2f6beee09c28d1fbd15eb06dd6b8fe08056))

## [0.12.1](https://github.com/xSAVIKx/agent-signals/compare/go/v0.12.0...go/v0.12.1) (2026-11-07)


### Bug Fixes

* **probes:** report a broken link in the layout instead of a shell error ([#102](https://github.com/xSAVIKx/agent-signals/issues/102)) ([e0b1671](https://github.com/xSAVIKx/agent-signals/commit/e0b1671056874a4782e607a6f2976dad90cae3d6))

## [0.12.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.11.0...go/v0.12.0) (2026-11-07)


### Features

* **probes:** run the Claude Code, agy and Cursor login steps on the fake model ([#98](https://github.com/xSAVIKx/agent-signals/issues/98)) ([836988e](https://github.com/xSAVIKx/agent-signals/commit/836988e1034051808ba2b06608627f8b9537c1cd))

## [0.11.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.10.0...go/v0.11.0) (2026-11-07)


### Features

* **probes:** add the fixture home mode with a fake model for Codex ([#96](https://github.com/xSAVIKx/agent-signals/issues/96)) ([72b89ae](https://github.com/xSAVIKx/agent-signals/commit/72b89aeca4c11109edf5accdd9864ea398c9be75))

## [0.10.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.9.0...go/v0.10.0) (2026-11-07)


### Features

* **facts:** measure early keys and the fast clear on Claude Code 2.1.316 and 2.1.318 ([#90](https://github.com/xSAVIKx/agent-signals/issues/90)) ([c7a4301](https://github.com/xSAVIKx/agent-signals/commit/c7a4301930f0fbdb4caed377ca0c1c130d3b84c8))

## [0.9.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.8.0...go/v0.9.0) (2026-11-01)


### Features

* **probes:** show the agy summaries status and the processes after a guided step ([#67](https://github.com/xSAVIKx/agent-signals/issues/67)) ([c0078f9](https://github.com/xSAVIKx/agent-signals/commit/c0078f952d5f64421f620ffbfdfa064b7dbd5d55))

## [0.8.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.7.0...go/v0.8.0) (2026-11-01)


### Features

* add fact 073, agy in the Debian VM of the Android Terminal app ([#63](https://github.com/xSAVIKx/agent-signals/issues/63)) ([ce0d3bd](https://github.com/xSAVIKx/agent-signals/commit/ce0d3bdfa6c6ea59c29f32711a1b8d85b4cfa542))


### Bug Fixes

* **probes:** skip the processes that start the kit when a guided step counts agent processes ([#66](https://github.com/xSAVIKx/agent-signals/issues/66)) ([afe26ac](https://github.com/xSAVIKx/agent-signals/commit/afe26acf00d2cd92a5ed2446d91f9a967c344ade))

## [0.7.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.6.0...go/v0.7.0) (2026-10-31)


### Features

* add facts 066 to 069 from the probe kit on macOS and Ubuntu ([#53](https://github.com/xSAVIKx/agent-signals/issues/53)) ([6b0a86d](https://github.com/xSAVIKx/agent-signals/commit/6b0a86de152de4286cb30cbdb2bc4198a10ac387))
* add facts 070 to 072 from the probe kit on Windows ([#55](https://github.com/xSAVIKx/agent-signals/issues/55)) ([ed1ea21](https://github.com/xSAVIKx/agent-signals/commit/ed1ea218791edbf4bd1b7d4e062c8bc559ef8270))

## [0.6.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.5.0...go/v0.6.0) (2026-10-31)


### Features

* add 14 agents, a CODEX_HOME run and more Windows agents to the first-run CI ([#41](https://github.com/xSAVIKx/agent-signals/issues/41)) ([f0637e8](https://github.com/xSAVIKx/agent-signals/commit/f0637e8b2ebf7b5812e9db40b19e6b16ebb30bf6))

## [0.5.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.4.0...go/v0.5.0) (2026-10-31)


### Features

* add a ConPTY driver and a first-run scenario for Windows ([#37](https://github.com/xSAVIKx/agent-signals/issues/37)) ([5452c4b](https://github.com/xSAVIKx/agent-signals/commit/5452c4b261d778ce16b2bb3e597a744981fbdb2c))
* add the first screens of 16 more agents with no login ([#34](https://github.com/xSAVIKx/agent-signals/issues/34)) ([cf0649d](https://github.com/xSAVIKx/agent-signals/commit/cf0649d77573c58c052cea25db102d57ab1557a6))

## [0.4.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.3.0...go/v0.4.0) (2026-10-30)


### Features

* add Codex scenarios for a denial, interrupts, hooks and the daemon ([#30](https://github.com/xSAVIKx/agent-signals/issues/30)) ([7b6440e](https://github.com/xSAVIKx/agent-signals/commit/7b6440e690b8aeedbe294f0c8cc54545627194b3))
* add facts 031 to 035, more Claude Code waits and a resume ([#27](https://github.com/xSAVIKx/agent-signals/issues/27)) ([ca5740d](https://github.com/xSAVIKx/agent-signals/commit/ca5740d9a06ea49fac27bd4bd5d5c74686f46b9e))
* measure more agy 1.4.7 signals (facts 041 to 045) ([#26](https://github.com/xSAVIKx/agent-signals/issues/26)) ([5922f5a](https://github.com/xSAVIKx/agent-signals/commit/5922f5aa527bf72b8532b3f16aac503e4aebccf4))
* run the probes and scenarios on each free runner image, with facts 046 to 050 ([#25](https://github.com/xSAVIKx/agent-signals/issues/25)) ([793ee1b](https://github.com/xSAVIKx/agent-signals/commit/793ee1b7f7e3069fd6eb9f703afba2f845b37ddb))


### Bug Fixes

* keep version numbers out of the IP rule of the scrub ([#33](https://github.com/xSAVIKx/agent-signals/issues/33)) ([94fa3f5](https://github.com/xSAVIKx/agent-signals/commit/94fa3f5e8322cf7ebfa9cb5be9980325b2090316))

## [0.3.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.2.0...go/v0.3.0) (2026-10-30)


### Features

* add fact 030, the first start of four more agents ([#22](https://github.com/xSAVIKx/agent-signals/issues/22)) ([78bff0c](https://github.com/xSAVIKx/agent-signals/commit/78bff0c8277aa2fd560249ce923dc762f4a38b80))

## [0.2.0](https://github.com/xSAVIKx/agent-signals/compare/go/v0.1.0...go/v0.2.0) (2026-10-30)


### Features

* add Codex CLI 0.164.0 screens: idle, busy and the F2 Warnings view ([#17](https://github.com/xSAVIKx/agent-signals/issues/17)) ([de64562](https://github.com/xSAVIKx/agent-signals/commit/de64562ed2dea71c29efce58e5e6b15b89855c99))
* add fact 029, the first start of each agent with no login ([#20](https://github.com/xSAVIKx/agent-signals/issues/20)) ([4035d26](https://github.com/xSAVIKx/agent-signals/commit/4035d26b9e3da68be2695905bd0b776d325e9732))
* add the agy turn scenario and its fact ([#14](https://github.com/xSAVIKx/agent-signals/issues/14)) ([fa47abe](https://github.com/xSAVIKx/agent-signals/commit/fa47abe591c95ed9c75c4aa376310e33e500b70b))
* add the Claude permission scenario and its facts ([#12](https://github.com/xSAVIKx/agent-signals/issues/12)) ([c14c386](https://github.com/xSAVIKx/agent-signals/commit/c14c386494cb142dff5336c1a7b7c4c1d3e16731))
* add the Codex approval scenarios and their facts ([#13](https://github.com/xSAVIKx/agent-signals/issues/13)) ([0d336bd](https://github.com/xSAVIKx/agent-signals/commit/0d336bd2d0dd37a79d84ce6d42c9c69d67165181))
* add the Cursor CLI macOS probe and its first facts ([#8](https://github.com/xSAVIKx/agent-signals/issues/8)) ([1e7c981](https://github.com/xSAVIKx/agent-signals/commit/1e7c9810af5ea107868fe4691218191dd4bc4946))

## 0.1.0 (2026-10-24)


### Features

* add Codex CLI 0.163.0 screens and facts ([#5](https://github.com/xSAVIKx/agent-signals/issues/5)) ([3f65f0c](https://github.com/xSAVIKx/agent-signals/commit/3f65f0cdb7a84f7b8c61c6b67951219f7f9ffd06))
* **go:** add a Go library that loads the corpus ([#4](https://github.com/xSAVIKx/agent-signals/issues/4)) ([b033130](https://github.com/xSAVIKx/agent-signals/commit/b03313074f9b92e174053c8a7e6b34710e1b2d7d))
