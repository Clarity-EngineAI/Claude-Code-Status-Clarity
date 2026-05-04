@echo off
setlocal

:: Look for bash in common Git for Windows install paths
if exist "%ProgramFiles%\Git\bin\bash.exe" (
  "%ProgramFiles%\Git\bin\bash.exe" "%~dp0statusline.sh"
  exit /b %errorlevel%
)
if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" (
  "%ProgramFiles(x86)%\Git\bin\bash.exe" "%~dp0statusline.sh"
  exit /b %errorlevel%
)
if exist "%LocalAppData%\Programs\Git\bin\bash.exe" (
  "%LocalAppData%\Programs\Git\bin\bash.exe" "%~dp0statusline.sh"
  exit /b %errorlevel%
)

:: Fall back to bash in PATH (works if Git for Windows bin is in PATH)
bash "%~dp0statusline.sh"
