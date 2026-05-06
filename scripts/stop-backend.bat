@echo off
REM ODIN 内容中台 - 后端停止脚本 (Windows)
REM 停止 Tomcat 后端服务

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0

REM 加载平台配置
call "%SCRIPT_DIR%config\windows.env"

set CATALINA_BASE=%BACKEND_DIR%\.tomcat

echo =========================================
echo ODIN 内容中台 - 后端停止
echo =========================================

REM 查找占用端口的进程
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%BACKEND_PORT% " ^| findstr "LISTENING"') do set PID=%%a

if not defined PID (
    echo 端口 %BACKEND_PORT% 未被占用，后端未运行
    exit /b 0
)

echo 发现进程 %PID% 占用端口 %BACKEND_PORT%
netstat -ano | findstr ":%BACKEND_PORT% "

REM 使用 Tomcat 脚本停止
if exist "%CATALINA_BASE%" (
    set CATALINA_HOME=%TOMCAT_HOME%
    echo.
    echo 使用 catalina.bat stop 停止...
    call "%TOMCAT_HOME%\bin\catalina.bat" stop 2>/dev/null

    timeout /t 3 /nobreak >/dev/null

    REM 检查是否停止成功
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%BACKEND_PORT% " ^| findstr "LISTENING" 2^>nul') do set PID_CHECK=%%a
    if defined PID_CHECK (
        echo 进程仍在运行，强制终止...
        taskkill /PID %PID% /F >/dev/null 2>&1
    )
) else (
    echo 强制终止进程 %PID%...
    taskkill /PID %PID% /F >/dev/null 2>&1
)

timeout /t 1 /nobreak >/dev/null

REM 最终检查
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%BACKEND_PORT% " ^| findstr "LISTENING" 2^>nul') do set PID_FINAL=%%a
if defined PID_FINAL (
    echo 停止失败，请手动检查
) else (
    echo.
    echo =========================================
    echo 后端已停止
    echo =========================================
)

endlocal
