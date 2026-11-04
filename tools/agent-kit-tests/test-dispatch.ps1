# The dispatcher of the agent kit on Windows.
. (Join-Path $env:ROOT 'tools/agent-kit-tests/lib.ps1')

Expect-Code 'no command is bad use' 2 (Invoke-Kit)
Expect-Line 'the help lists the commands' '^commands:$' (Join-Path $T 'out')
Expect-Code 'an unknown command is bad use' 2 (Invoke-Kit 'no-such')
Expect-Code 'a path is not a command' 2 (Invoke-Kit '..\lib')
Expect-Code 'version exits 0' 0 (Invoke-Kit 'version')

Complete-Tests
