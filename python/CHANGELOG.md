# Changelog

## [0.11.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.10.0...python-v0.11.0) (2026-11-09)


### Features

* **scenarios:** measure Claude Code after its pipes close and the Codex app-server status ([#124](https://github.com/xSAVIKx/agent-signals/issues/124)) ([6e89c43](https://github.com/xSAVIKx/agent-signals/commit/6e89c435e77fab45b707b72cd1abeecc93fca625))

## [0.10.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.9.2...python-v0.10.0) (2026-11-08)


### Features

* **probes:** run opencode with the fake model and measure when it asks ([#122](https://github.com/xSAVIKx/agent-signals/issues/122)) ([73d90da](https://github.com/xSAVIKx/agent-signals/commit/73d90da4664e4cfd2e3a8af46e288bcd34d8f6f7))

## [0.9.2](https://github.com/xSAVIKx/agent-signals/compare/python-v0.9.1...python-v0.9.2) (2026-11-08)


### Bug Fixes

* **probes:** keep work folders out of temp folders and pass JSON args on Windows ([#120](https://github.com/xSAVIKx/agent-signals/issues/120)) ([99450ef](https://github.com/xSAVIKx/agent-signals/commit/99450ef3a5815c3eead82d560005889c2793f6b5))

## [0.9.1](https://github.com/xSAVIKx/agent-signals/compare/python-v0.9.0...python-v0.9.1) (2026-11-08)


### Bug Fixes

* **corpus:** measure fact 085 with the run folder outside the temp folders ([#118](https://github.com/xSAVIKx/agent-signals/issues/118)) ([6e219ac](https://github.com/xSAVIKx/agent-signals/commit/6e219ac7648e74a9419256c02ce5e791c00eb053))

## [0.9.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.8.0...python-v0.9.0) (2026-11-08)


### ⚠ BREAKING CHANGES

* **python:** the package no longer installs on Python 3.10.

### Features

* **probes:** record the conditions of each session step and add one step for each mode ([#116](https://github.com/xSAVIKx/agent-signals/issues/116)) ([616d5de](https://github.com/xSAVIKx/agent-signals/commit/616d5de14e0bd72c7a324849838cd2a98585da1e))


### Build System

* **python:** require Python 3.11 or later ([#117](https://github.com/xSAVIKx/agent-signals/issues/117)) ([78ec4a8](https://github.com/xSAVIKx/agent-signals/commit/78ec4a88c9312c9dc2095b2e0e9bd8cdb9f98739))

## [0.8.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.7.2...python-v0.8.0) (2026-11-08)


### Features

* **go:** add the file-write texts "Write a file" and "Write outside" to the fake model ([#112](https://github.com/xSAVIKx/agent-signals/issues/112)) ([70c2cbe](https://github.com/xSAVIKx/agent-signals/commit/70c2cbe9de9510ae6eee8fd077a5c9875c14dc27))

## [0.7.2](https://github.com/xSAVIKx/agent-signals/compare/python-v0.7.1...python-v0.7.2) (2026-11-07)


### Bug Fixes

* **probes:** fixes from the unattended runs of 0.16.0 ([#110](https://github.com/xSAVIKx/agent-signals/issues/110)) ([c3758dc](https://github.com/xSAVIKx/agent-signals/commit/c3758dce81679765ce35475634b93cb7efeba014))

## [0.7.1](https://github.com/xSAVIKx/agent-signals/compare/python-v0.7.0...python-v0.7.1) (2026-11-07)


### Bug Fixes

* **probes:** report a broken link in the layout instead of a shell error ([#102](https://github.com/xSAVIKx/agent-signals/issues/102)) ([e0b1671](https://github.com/xSAVIKx/agent-signals/commit/e0b1671056874a4782e607a6f2976dad90cae3d6))


### Documentation

* **facts:** add facts 80 and 81, the macOS procStart form and the Cursor worker process ([#100](https://github.com/xSAVIKx/agent-signals/issues/100)) ([42dd9f2](https://github.com/xSAVIKx/agent-signals/commit/42dd9f2dd6d01fe4e80343ae73b62016442e549a))

## [0.7.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.6.0...python-v0.7.0) (2026-11-07)


### Features

* **probes:** run the Claude Code, agy and Cursor login steps on the fake model ([#98](https://github.com/xSAVIKx/agent-signals/issues/98)) ([836988e](https://github.com/xSAVIKx/agent-signals/commit/836988e1034051808ba2b06608627f8b9537c1cd))

## [0.6.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.5.0...python-v0.6.0) (2026-11-07)


### Features

* **probes:** add the fixture home mode with a fake model for Codex ([#96](https://github.com/xSAVIKx/agent-signals/issues/96)) ([72b89ae](https://github.com/xSAVIKx/agent-signals/commit/72b89aeca4c11109edf5accdd9864ea398c9be75))

## [0.5.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.4.0...python-v0.5.0) (2026-11-07)


### Features

* **facts:** measure early keys and the fast clear on Claude Code 2.1.316 and 2.1.318 ([#90](https://github.com/xSAVIKx/agent-signals/issues/90)) ([c7a4301](https://github.com/xSAVIKx/agent-signals/commit/c7a4301930f0fbdb4caed377ca0c1c130d3b84c8))

## [0.4.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.3.0...python-v0.4.0) (2026-11-01)


### Features

* **probes:** show the agy summaries status and the processes after a guided step ([#67](https://github.com/xSAVIKx/agent-signals/issues/67)) ([c0078f9](https://github.com/xSAVIKx/agent-signals/commit/c0078f952d5f64421f620ffbfdfa064b7dbd5d55))

## [0.3.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.2.0...python-v0.3.0) (2026-11-01)


### Features

* add fact 073, agy in the Debian VM of the Android Terminal app ([#63](https://github.com/xSAVIKx/agent-signals/issues/63)) ([ce0d3bd](https://github.com/xSAVIKx/agent-signals/commit/ce0d3bdfa6c6ea59c29f32711a1b8d85b4cfa542))


### Bug Fixes

* **probes:** skip the processes that start the kit when a guided step counts agent processes ([#66](https://github.com/xSAVIKx/agent-signals/issues/66)) ([afe26ac](https://github.com/xSAVIKx/agent-signals/commit/afe26acf00d2cd92a5ed2446d91f9a967c344ade))

## [0.2.0](https://github.com/xSAVIKx/agent-signals/compare/python-v0.1.0...python-v0.2.0) (2026-10-31)


### Features

* add facts 066 to 069 from the probe kit on macOS and Ubuntu ([#53](https://github.com/xSAVIKx/agent-signals/issues/53)) ([6b0a86d](https://github.com/xSAVIKx/agent-signals/commit/6b0a86de152de4286cb30cbdb2bc4198a10ac387))
* add facts 070 to 072 from the probe kit on Windows ([#55](https://github.com/xSAVIKx/agent-signals/issues/55)) ([ed1ea21](https://github.com/xSAVIKx/agent-signals/commit/ed1ea218791edbf4bd1b7d4e062c8bc559ef8270))

## 0.1.0 (2026-10-31)


### Features

* add 14 agents, a CODEX_HOME run and more Windows agents to the first-run CI ([#41](https://github.com/xSAVIKx/agent-signals/issues/41)) ([f0637e8](https://github.com/xSAVIKx/agent-signals/commit/f0637e8b2ebf7b5812e9db40b19e6b16ebb30bf6))
* **python:** add a Python library that loads the corpus ([#39](https://github.com/xSAVIKx/agent-signals/issues/39)) ([e655ac3](https://github.com/xSAVIKx/agent-signals/commit/e655ac378443f814e2bdfea4ad3a028028901dc2))
