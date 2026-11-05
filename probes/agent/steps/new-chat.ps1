# The step kind "new-chat" on Windows: a test session that starts a new
# chat. kit step runs probes\agent\steps\<kind>.ps1, and this kind runs
# session-step.ps1.
& (Join-Path $PSScriptRoot 'session-step.ps1') @args
exit $LASTEXITCODE
