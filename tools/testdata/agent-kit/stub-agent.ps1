# A stub agent for the tests of `kit session` on Windows. It is the twin of
# tools/testdata/agent-kit/stub-agent.sh.
#
# It draws "stub idle" and a prompt line. On the text "write" and Enter it
# draws a permission dialog. On "1" it writes agent-signals-test.txt in
# its working folder. On "2" or Escape it goes back to idle. On the text
# "busy" and Enter it draws a busy screen with the text "esc to
# interrupt", and it stays busy until Escape. On the text "stream" and
# Enter it draws a new number each 0.3 s with no busy line until Escape, as
# Codex 0.167.2 did on a real model. C-u clears the prompt line.
#
# When STUB_LOG is set, it writes one line for each key to that file:
# "key Enter", "key Escape", "key Tab", or "char N" (N is the code of the
# character). A test reads the file to see the bytes that a backend sent.
# The kit gives the agent a clean environment, so a test sets STUB_LOG and
# STUB_ENV in the --cmd of the session.
#
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File stub-agent.ps1
$ErrorActionPreference = 'Stop'

# Let the console read VT sequences, so that the clear and the cursor
# moves work in each console host.
$code = @'
using System;
using System.Runtime.InteropServices;
// StubStream draws a new number each 0.3 s from a timer thread while the
// main thread waits in ReadKey. A loop on Console.KeyAvailable did not
// redraw under ConPTY in CI.
public static class StubStream {
    static System.Threading.Timer timer;
    static int n;
    public static void Start() {
        n = 0;
        timer = new System.Threading.Timer(delegate(object o) {
            n++;
            Console.Out.Write("\x1b[2J\x1b[3J\x1b[Hstub output\r\n\r\n" + (n + 1) + "\r\n" + (n + 2) + "\r\n" + (n + 3));
            Console.Out.Flush();
        }, null, 300, 300);
    }
    public static void Stop() {
        if (timer != null) { timer.Dispose(); timer = null; }
    }
}
public static class StubConsole {
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);
    public static void EnableVt() {
        IntPtr h = GetStdHandle(-11);
        uint m;
        if (GetConsoleMode(h, out m)) { SetConsoleMode(h, m | 0x0004); }
    }
}
'@
try { Add-Type -TypeDefinition $code; [StubConsole]::EnableVt() } catch { }

$script:State = 'idle'
$script:Buffer = ''
$script:Note = ''
$esc = [char]27

# Write-Log LINE: add LINE to STUB_LOG. Another process (a virus scanner,
# or a reader of the log) can hold the file for a moment. With "Stop", a
# failed write ended the stub, and the step then failed with agent-ended.
# So the stub opens the file with all sharing, tries again 20 times at
# most, 50 ms apart, and then drops the line.
function Write-Log([string]$Line) {
    if (-not $env:STUB_LOG) { return }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Line + "`r`n")
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $fs = New-Object System.IO.FileStream($env:STUB_LOG, [IO.FileMode]::Append, [IO.FileAccess]::Write, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            return
        } catch { Start-Sleep -Milliseconds 50 }
    }
}

# When STUB_ENV is set, write the names of the environment variables to
# that file, one on each line, so that a test can check the environment.
if ($env:STUB_ENV) {
    Get-ChildItem Env: | ForEach-Object { $_.Name } | Sort-Object | Set-Content -LiteralPath $env:STUB_ENV
}

function Show-Screen {
    $lines = @()
    if ($script:State -eq 'idle') {
        $lines += 'stub idle'
        if ($script:Note) { $lines += $script:Note }
        $lines += ''
        $last = "> $($script:Buffer)"
    } elseif ($script:State -eq 'busy') {
        $lines += 'stub busy'
        $lines += ''
        $lines += '* Counting (esc to interrupt)'
        $last = ''
    } elseif ($script:State -eq 'stream') {
        # Not "stub stream": the step must not see its prompt "stream" on
        # the screen.
        $lines += 'stub output'
        $lines += ''
        $lines += '1'
        $lines += '2'
        $last = '3'
    } else {
        $lines += 'Do you want to create agent-signals-test.txt?'
        $lines += '1. Yes'
        $lines += '2. No'
        $last = ''
    }
    $text = "$esc[2J$esc[3J$esc[H" + (($lines + $last) -join "`r`n")
    [Console]::Out.Write($text)
    [Console]::Out.Flush()
}

Show-Screen
while ($true) {
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
        'Enter' { Write-Log 'key Enter' }
        'Escape' { Write-Log 'key Escape' }
        'Tab' { Write-Log 'key Tab' }
        default { Write-Log ("char " + [int]$k.KeyChar) }
    }
    if ($script:State -eq 'idle') {
        if ($k.Key -eq 'Enter') {
            if ($script:Buffer -eq 'write') { $script:State = 'dialog' }
            elseif ($script:Buffer -eq 'busy') { $script:State = 'busy' }
            elseif ($script:Buffer -eq 'stream') { $script:State = 'stream'; [StubStream]::Start() }
            $script:Buffer = ''
        } elseif ($k.Key -eq 'Escape') {
            $script:Buffer = ''
        } elseif ([int]$k.KeyChar -eq 21) {
            # C-u clears the box. The step sends it before it types the
            # prompt again. Without it, the box held "busybusy", and the
            # stub did not become busy.
            $script:Buffer = ''
        } elseif ($k.Key -eq 'Backspace') {
            if ($script:Buffer.Length -gt 0) { $script:Buffer = $script:Buffer.Substring(0, $script:Buffer.Length - 1) }
        } elseif ([int]$k.KeyChar -ge 32) {
            $script:Buffer += $k.KeyChar
        }
    } elseif ($script:State -eq 'busy' -or $script:State -eq 'stream') {
        if ($k.Key -eq 'Escape') {
            if ($script:State -eq 'stream') { [StubStream]::Stop(); Start-Sleep -Milliseconds 400 }
            $script:State = 'idle'
            $script:Note = 'interrupted'
        }
    } else {
        if ($k.KeyChar -eq '1') {
            Set-Content -LiteralPath (Join-Path (Get-Location).Path 'agent-signals-test.txt') -Value 'agent-signals test'
            $script:Note = 'stub wrote agent-signals-test.txt'
            $script:State = 'idle'
        } elseif ($k.KeyChar -eq '2' -or $k.Key -eq 'Escape') {
            $script:Note = ''
            $script:State = 'idle'
        }
    }
    Show-Screen
}
