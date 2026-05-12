#!/bin/bash
# 停止后端服务

if [ -f /tmp/odin-server.pid ]; then
    PID=$(cat /tmp/odin-server.pid)
    echo "停止服务 (PID: $PID)..."
    kill $PID 2>/dev/null
    rm /tmp/odin-server.pid
    echo "服务已停止"
else
    echo "查找运行中的 Java 进程..."
    PIDS=$(ps aux | grep 'spring-boot' | grep -v grep | awk '{print $2}')
    if [ -n "$PIDS" ]; then
        echo "停止进程: $PIDS"
        kill $PIDS 2>/dev/null
        echo "服务已停止"
    else
        echo "未找到运行中的服务"
    fi
fi