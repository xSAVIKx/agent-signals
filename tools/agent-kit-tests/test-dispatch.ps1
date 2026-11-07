# The dispatcher of the agent kit on Windows.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')

Expect-Code 'no command is bad use' 2 (Invoke-Kit)
Expect-Line 'the help lists the commands' '^commands:$' (Join-Path $T 'out')
Expect-Code 'an unknown command is bad use' 2 (Invoke-Kit 'no-such')
Expect-Code 'a path is not a command' 2 (Invoke-Kit '..\lib')
Expect-Code 'version exits 0' 0 (Invoke-Kit 'version')

# A command gets its arguments as an array, also with one or no argument.
$cmdFile = Join-Path $env:ROOT 'probes/agent/zz-args.ps1'
Set-Content -LiteralPath $cmdFile -Value 'Write-Output "n=$($args.Count) first=$($args[0])"; exit 0'
try {
    Invoke-Kit 'zz-args' | Out-Null
    Expect-Line 'no argument gives an empty array' '^n=0 first=$' (Join-Path $T 'out')
    Invoke-Kit 'zz-args' 'abc' | Out-Null
    Expect-Line 'one argument stays one string' '^n=1 first=abc$' (Join-Path $T 'out')
    Invoke-Kit 'zz-args' 'a b' 'c' | Out-Null
    Expect-Line 'two arguments stay two' '^n=2 first=a b$' (Join-Path $T 'out')
} finally {
    Remove-Item -LiteralPath $cmdFile -Force
}

Complete-Tests
