# 052. The first screens on Windows match the Linux screens

## Measured

2026-10-30, the scenario `scenarios/first-run-windows.py` in the scenarios
workflow (run 41146500448, and again in run 41145363320), with the agents
and versions of fact 51, a pseudo console of 120 x 40, a throwaway
profile, no login and no key. The screen after 20 s was compared with the
Linux screens of facts 29, 30 and 46.

Measured on: CI runner windows-2022 (x64), CI runner windows-2025 (x64) and
CI runner windows-11-arm (arm64).

## What was measured

1. These agents showed the same first question as on Linux, with the same
   words and options, on the three images:
   - Claude Code 2.1.314: "Welcome to Claude Code v2.1.314", "Let's get
     started." and "Choose the text style that looks best with your
     terminal", with "> √   Dark mode" selected (fact 29).
   - Codex CLI 0.166.0: "Choose how you want to use Codex." with "1. Sign in
     with ChatGPT" to "4. Use Amazon Bedrock" (fact 29).
   - Cursor CLI: "Cursor Agent", "v2026.10.22-27dcf5f" and "Press any key to
     log in..." (fact 29).
   - Copilot CLI 1.0.105: "Confirm folder trust" with "❯ 1. Yes", "2. Yes,
     and remember this folder for future sessions" and "3. No (Esc)"
     (fact 30).
   - Gemini CLI 0.66.0: "Do you trust the files in this folder?" with
     "● 1. Trust folder (example)", "2. Trust parent folder (work)" and
     "3. Don't trust" (fact 30).
   - Amp: "No API key found. Starting login flow..." and "Would you like to
     log in to Amp? [(y)es, (n)o]:" (x64 only, fact 46).
   - Crush: "To start, let's choose a provider and model." and
     "> Find your fave" (fact 46).
   - Kimi Code CLI 2.4.1: "Trust this folder?" with "❯ Trust and continue"
     and "Exit" (fact 46).
   - Continue CLI 1.5.47: "To get started, enter your Anthropic API key."
     (fact 46).
   - Factory Droid 1.0.0: "Welcome to Factory CLI", "Please login with your
     Factory account to continue." and "> Login" (run 41145363320, fact 46).
   - Cline CLI 3.0.74: "Welcome to Cline", "Connect a model provider to get
     started." and four boxes from "Sign in with Cline" to "Bring your own
     provider" (fact 46).
   - Kilo Code CLI 7.8.18: the input box "Ask anything..." and "Code  · Auto
     Free Kilo Gateway" (fact 46).
   - Auggie 0.36.0: "New to Augment? You can create an account from the
     login page." and "→ Login to continue" (fact 46).
   - opencode 1.19.5: the input box "Ask anything…" and "/update to upgrade
     to OpenCode 2.0" (fact 29).
2. Qwen Code 0.26.4 showed a box "Connect a Provider" with "› QwenCloud"
   and "Alibaba ModelStudio". Fact 30 gives other words ("Choose a built-in
   provider and connect with an API key"). The Linux version of fact 30 was
   not compared.
3. Differences between the Windows images:
   - On windows-2022 only, Gemini CLI added "⚠  Warning: Windows 10
     detected. Some UI features like smooth scrolling may be degraded.
     Windows 11 is recommended for ...". Windows Server 2022 has the build
     number 20348.
   - Kimi Code CLI, Kilo Code CLI and opencode show the work folder as a
     Windows path, for example `D:\a\_temp\run.<id>\work\example` on x64
     and `C:\a\_temp\...` on arm64.
   - On windows-11-arm, Amp printed "This version of
     C:\npm\prefix\node_modules\@ampcode\cli\bin\amp.exe is not compatible
     with the version of Windows you're running." and exited (fact 48).

## Mechanism

These agents draw with the same code on Windows and on Linux. ConPTY
sends the screen as VT output, which the driver reads as tmux reads a pane.
A reader of the screens of facts 29, 30 and 46 can read the Windows screens
too, with these exceptions: Windows paths in the screen, and the Gemini
warning on Windows Server 2022.

## Incident

None.

## Screens

None. The screens are in the logs of the runs, not in the corpus.

## Not measured

- The styles (colors) of the screens. The driver gives plain text only.
- The screens after a key, a login or a turn.
- Windows Terminal or conhost.exe as the terminal. ConPTY can render
  differently in another host.
- Whether the Gemini warning shows on Windows 10 desktop builds.
