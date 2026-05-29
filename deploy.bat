@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo 🔄 Pull code moi nhat tu GitHub...

REM Check uncommitted changes
git diff --quiet
set NEED_STASH=%errorlevel%
git diff --cached --quiet
if errorlevel 1 set NEED_STASH=1

if "%NEED_STASH%"=="1" (
  echo    Co thay doi local — tam stash...
  REM No -u: -u would stash deploy.bat itself when untracked,
  REM causing cmd.exe to lose the script mid-execution.
  git stash push -m "deploy.bat auto-stash"
  if errorlevel 1 (
    echo ❌ Stash fail. Dung deploy.
    exit /b 1
  )
)

git pull --rebase
if errorlevel 1 (
  echo ❌ Pull fail — co the conflict.
  if "%NEED_STASH%"=="1" (
    echo    Restore stash...
    git stash pop
  )
  exit /b 1
)

if "%NEED_STASH%"=="1" (
  echo    Restore thay doi local...
  git stash pop
  if errorlevel 1 (
    echo ❌ Stash pop fail — co conflict.
    exit /b 1
  )
)

echo.
echo 🔍 Dang chay syntax check...
python check_syntax3.py
if errorlevel 1 (
  echo ❌ Syntax check fail. Dung deploy.
  exit /b 1
)

echo.
echo 🧪 Dang chay auto_test.py...
python auto_test.py
if errorlevel 1 (
  echo ⚠️  Auto test co loi nhung tiep tuc.
)

echo.
echo 📦 Dang commit...
git add .
git status --short

REM Commit message: argument hoac default timestamp
if "%~1"=="" (
  for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set TODAY=%%c-%%a-%%b
  for /f "tokens=1-2 delims=: " %%a in ('time /t') do set NOW=%%a-%%b
  set COMMIT_MSG=Update app !TODAY! !NOW!
) else (
  set COMMIT_MSG=%~1
)

git commit -m "!COMMIT_MSG!"
if errorlevel 1 (
  echo ℹ️  Khong co thay doi de commit.
  exit /b 0
)

echo.
echo 🚀 Dang push len GitHub...
git push
if errorlevel 1 (
  echo ❌ Push fail.
  exit /b 1
)

echo.
echo ✅ Deploy thanh cong!
echo 🌐 https://gendaisougo-vietnam.github.io/gsa
echo ⏰ Doi ~30 giay de GitHub Pages cap nhat.

endlocal
