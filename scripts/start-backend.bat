@echo off
REM ODIN 内容中台 - 后端启动脚本 (Windows)
REM 使用 Tomcat 启动后端服务

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0

REM 加载平台配置
call "%SCRIPT_DIR%config\windows.env"

set WEB_MODULE=%BACKEND_DIR%\mkt_odin_server_web
set WAR_EXPLODED=%WEB_MODULE%\target\ROOT

echo =========================================
echo ODIN 内容中台 - 后端启动
echo =========================================

REM 检查端口是否被占用
netstat -ano | findstr ":%BACKEND_PORT% " | findstr "LISTENING" >/dev/null 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%BACKEND_PORT% " ^| findstr "LISTENING"') do (
        echo 端口 %BACKEND_PORT% 已被占用 (PID: %%a)
        echo 正在停止...
        taskkill /F /PID %%a >/dev/null 2>&1
        timeout /t 2 /nobreak >/dev/null
    )
)

REM 检查编译产物是否存在
if not exist "%WAR_EXPLODED%\WEB-INF" (
    echo WAR exploded 不存在，请先编译:
    echo   mvn clean package -DskipTests -Plocal -pl mkt_odin_server_web -am
    exit /b 1
)

REM 设置 JAVA_HOME
if not defined JAVA_HOME (
    echo 错误: JAVA_HOME 未设置
    echo 请在 config\windows.env 中配置 JAVA_HOME
    exit /b 1
)

echo JAVA_HOME: %JAVA_HOME%
"%JAVA_HOME%\bin\java" -version

REM 配置 CATALINA_BASE
set CATALINA_BASE=%BACKEND_DIR%\.tomcat
if not exist "%CATALINA_BASE%\logs" mkdir "%CATALINA_BASE%\logs"
if not exist "%CATALINA_BASE%\temp" mkdir "%CATALINA_BASE%\temp"
if not exist "%CATALINA_BASE%\work" mkdir "%CATALINA_BASE%\work"
if not exist "%CATALINA_BASE%\webapps" mkdir "%CATALINA_BASE%\webapps"
if not exist "%CATALINA_BASE%\conf\Catalina\localhost" mkdir "%CATALINA_BASE%\conf\Catalina\localhost"
if not exist "%CATALINA_BASE%\bin" mkdir "%CATALINA_BASE%\bin"

REM 复制 Tomcat 配置文件 (强制覆盖)
copy /Y "%TOMCAT_HOME%\conf\server.xml" "%CATALINA_BASE%\conf\" >/dev/null
copy /Y "%TOMCAT_HOME%\conf\web.xml" "%CATALINA_BASE%\conf\" >/dev/null
copy /Y "%TOMCAT_HOME%\conf\context.xml" "%CATALINA_BASE%\conf\" >/dev/null
if exist "%TOMCAT_HOME%\conf\logging.properties" (
    copy /Y "%TOMCAT_HOME%\conf\logging.properties" "%CATALINA_BASE%\conf\" >/dev/null
) else (
    echo [WARN] logging.properties not found
)

REM 创建 context 配置
echo ^<?xml version="1.0" encoding="UTF-8"?^> > "%CATALINA_BASE%\conf\Catalina\localhost\ROOT.xml"
echo ^<Context docBase="%WAR_EXPLODED%" reloadable="true"/^> >> "%CATALINA_BASE%\conf\Catalina\localhost\ROOT.xml"

REM 设置环境变量
set CATALINA_HOME=%TOMCAT_HOME%

REM Java 8 不需要 --add-opens 参数

echo.
echo 启动 Tomcat...
echo CATALINA_HOME: %CATALINA_HOME%
echo CATALINA_BASE: %CATALINA_BASE%
echo WAR exploded: %WAR_EXPLODED%
echo.

REM 清空旧日志
del /Q "%CATALINA_BASE%\logs\*.*" 2>/dev/null

REM 启动 Tomcat
call "%TOMCAT_HOME%\bin\catalina.bat" start

echo 等待应用启动...
timeout /t 15 /nobreak >/dev/null

REM 检查是否启动成功
netstat -ano | findstr ":%BACKEND_PORT% " | findstr "LISTENING" >/dev/null 2>&1
if %errorlevel% equ 0 (
    echo.
    echo =========================================
    echo 后端启动成功!
    echo 地址: http://localhost:%BACKEND_PORT%
    echo 日志目录: %CATALINA_BASE%\logs\
    echo =========================================

    REM 测试 API
    echo.
    echo 测试 API...
    curl -s http://localhost:%BACKEND_PORT%/api/tag/category/tree
) else (
    echo.
    echo 启动可能失败，请检查日志:
    echo dir "%CATALINA_BASE%\logs\"
)

endlocal
