# The step kind "interrupt" on Windows: a test session with a long prompt,
# then the answer keys while the agent works. kit step runs
# probes\agent\steps\<kind>.ps1, and this kind runs session-step.ps1.
& (Join-Path $PSScriptRoot 'session-step.ps1') @args
exit $LASTEXITCODE
