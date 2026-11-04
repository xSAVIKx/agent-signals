# A stub agent for the tests of `kit session` on Windows. It is the twin of
# tools/testdata/agent-kit/stub-agent.sh.
#
# It draws "stub idle" and a prompt line. On the text "write" and Enter it
# draws a permission dialog. On "1" it writes agent-signals-test.txt in
# its working folder. On "2" or Escape it goes back to idle.
#
# When STUB_LOG is set, it writes one line for each key to that file:
# "key Enter", "key Escape", "key Tab", or "char N" (N is the code of the
# character). A test reads the file to see the bytes that a backend sent.
#
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File stub-agent.ps1
$ErrorActionPreference = 'Stop'

# Let the console read VT sequences, so that the clear and the cursor
# moves work in each console host.
$code = @'
using System;
using System.Runtime.InteropServices;
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

function Write-Log([string]$Line) {
    if ($env:STUB_LOG) { Add-Content -LiteralPath $env:STUB_LOG -Value $Line }
}

function Show-Screen {
    $lines = @()
    if ($script:State -eq 'idle') {
        $lines += 'stub idle'
        if ($script:Note) { $lines += $script:Note }
        $lines += ''
        $last = "> $($script:Buffer)"
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
            $script:Buffer = ''
        } elseif ($k.Key -eq 'Escape') {
            $script:Buffer = ''
        } elseif ($k.Key -eq 'Backspace') {
            if ($script:Buffer.Length -gt 0) { $script:Buffer = $script:Buffer.Substring(0, $script:Buffer.Length - 1) }
        } elseif ([int]$k.KeyChar -ge 32) {
            $script:Buffer += $k.KeyChar
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
