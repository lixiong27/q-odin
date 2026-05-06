@echo off
REM ODIN 运营平台 - 前端启动脚本 (Windows)
REM 使用 Node v12.16.1 启动前端开发服务器

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0

REM 加载平台配置
call "%SCRIPT_DIR%config\windows.env"

echo =========================================
echo ODIN 运营平台 - 前端启动
echo =========================================

REM 进入前端目录
cd /d "%FRONTEND_DIR%"

REM 设置 OpenSSL legacy provider (解决 Node 17+ 与 Webpack 4 兼容问题)
set NODE_OPTIONS=--openssl-legacy-provider

REM 切换 Node 版本 (需要安装 nvm-windows)
echo 切换到 Node %NODE_VERSION%...
where nvm >nul 2>&1
if %errorlevel% equ 0 (
    call nvm use %NODE_VERSION%
) else (
    echo 警告: nvm 未安装，使用系统默认 Node
)

REM 验证 Node 版本
echo 当前 Node 版本:
node -v
echo 当前 npm 版本:
npm -v

REM 启动前端
echo 启动前端开发服务器...
echo 前端地址: http://localhost:%FRONTEND_PORT%
echo 后端代理: http://localhost:%BACKEND_PORT%
echo =========================================
call npm start

endlocal
