@echo off
rem The stub agent of the kit tests, on PATH as "claude".
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\stub-agent.ps1" %*
