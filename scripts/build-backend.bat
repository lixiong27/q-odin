@echo off
REM ODIN 运营平台 - 后端编译脚本 (Windows)
REM 编译后端项目

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0

REM 加载平台配置
call "%SCRIPT_DIR%config\windows.env"

echo =========================================
echo ODIN 运营平台 - 后端编译
echo =========================================

REM 设置 JAVA_HOME
if not defined JAVA_HOME (
    echo 错误: JAVA_HOME 未设置
    echo 请在 config\windows.env 中配置 JAVA_HOME
    exit /b 1
)

echo JAVA_HOME: %JAVA_HOME%

REM 进入后端目录
cd /d "%BACKEND_DIR%"

echo.
echo 开始编译...
echo.

REM 编译项目
call mvn clean package -DskipTests

if %errorlevel% equ 0 (
    echo.
    echo =========================================
    echo 编译成功!
    echo 输出目录: %BACKEND_DIR%\mkt_odin_server_web\target\ROOT
    echo =========================================
) else (
    echo.
    echo =========================================
    echo 编译失败，请检查错误信息
    echo =========================================
    exit /b 1
)

endlocal
