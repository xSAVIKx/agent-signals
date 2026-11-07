# The step kind "permission" on Windows: a test session with a file write
# prompt. kit step runs probes\agent\steps\<kind>.ps1, and this kind runs
# session-step.ps1.
& (Join-Path $PSScriptRoot 'session-step.ps1') @args
exit $LASTEXITCODE
