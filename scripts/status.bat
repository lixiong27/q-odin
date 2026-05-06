@echo off
REM ODIN 运营平台 - 状态检查脚本 (Windows)
REM 检查前后端服务运行状态

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0

REM 加载平台配置
call "%SCRIPT_DIR%config\windows.env"

echo =========================================
echo ODIN 运营平台 - 服务状态
echo =========================================

REM 检查后端状态
echo.
echo 【后端服务】端口 %BACKEND_PORT%
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%BACKEND_PORT% " ^| findstr "LISTENING" 2^>nul') do set BACKEND_PID=%%a

if defined BACKEND_PID (
    echo 状态: 运行中 (PID: %BACKEND_PID%)
    echo 地址: http://localhost:%BACKEND_PORT%

    REM 健康检查
    curl -s -o nul -w "%%{http_code}" http://localhost:%BACKEND_PORT%/health >nul 2>&1
    if %errorlevel% equ 0 (
        echo 健康检查: 正常
    ) else (
        echo 健康检查: 异常
    )
) else (
    echo 状态: 未运行
)

REM 检查前端状态
echo.
echo 【前端服务】端口 %FRONTEND_PORT%
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%FRONTEND_PORT% " ^| findstr "LISTENING" 2^>nul') do set FRONTEND_PID=%%a

if defined FRONTEND_PID (
    echo 状态: 运行中 (PID: %FRONTEND_PID%)
    echo 地址: http://localhost:%FRONTEND_PORT%
    echo Node 版本: 使用 node -v 查看
) else (
    echo 状态: 未运行
)

REM 检查数据库连接
echo.
echo 【数据库连接】
echo 环境: local
echo 数据库: mkt_ares_live

echo.
echo =========================================
echo 快速命令:
echo   启动后端: scripts\start-backend.bat
echo   停止后端: scripts\stop-backend.bat
echo   启动前端: scripts\start-frontend.bat
echo   停止前端: scripts\stop-frontend.bat
echo   查看状态: scripts\status.bat
echo =========================================

endlocal
