#!/bin/bash
# 启动后端服务

cd /d/Users/qixiong.li/personal/q-odin/odin_server

echo "=== 1. 编译项目 ==="
mvn compile -pl mkt_odin_server_web -am -q
if [ $? -ne 0 ]; then
    echo "编译失败！"
    exit 1
fi
echo "编译成功"

echo "=== 2. 启动服务 ==="
mvn spring-boot:run -pl mkt_odin_server_web &

# 记录 PID
echo $! > /tmp/odin-server.pid

# 等待服务启动
echo "等待服务启动..."
for i in $(seq 1 30); do
    sleep 2
    status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null)
    if [ "$status" = "200" ]; then
        echo "服务启动成功！"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "服务启动超时"
        exit 1
    fi
done