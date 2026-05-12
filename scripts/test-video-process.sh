#!/bin/bash
# 测试视频处理全流程

VIDEO_URL="https://qimgs.qunarzz.com/mkt_dmp_0001/38c7900fc5774923aec5dcc9ae2b5b5c.mp4"

echo "=== 视频处理全流程测试 ==="
echo "视频URL: $VIDEO_URL"
echo ""

# 检查服务是否运行
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null)
if [ "$STATUS" != "200" ]; then
    echo "错误: 服务未启动，请先运行 start-server.sh"
    exit 1
fi

echo "开始处理..."
echo ""

START_TIME=$(date +%s%N)

RESULT=$(curl -s -X POST http://localhost:8080/api/ai/video/process/demo \
  -H "Content-Type: application/json" \
  -d "{\"videoUrl\":\"$VIDEO_URL\",\"title\":\"测试视频\",\"enableAsr\":true}")

END_TIME=$(date +%s%N)
TOTAL_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo "=== 原始响应 ==="
echo "$RESULT" | python -m json.tool 2>/dev/null || echo "$RESULT"

echo ""
echo "=== 视频处理结果摘要 ==="

# 提取关键字段 (如python可用则用python解析)
if command -v python &> /dev/null; then
    CODE=$(echo "$RESULT" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','N/A'))" 2>/dev/null)
    if [ "$CODE" = "0" ]; then
        echo "状态: 成功"

        echo ""
        echo "--- 抽帧结果 (OSS URL) ---"
        echo "$RESULT" | python -c "
import sys, json
d = json.load(sys.stdin)
for i, url in enumerate(d.get('frameUrls', [])):
    print(f'  第{i+1}帧: {url}')
print(f'抽帧数量: {d.get(\"frameCount\", 0)}')
"

        echo ""
        echo "--- 音频结果 ---"
        echo "$RESULT" | python -c "
import sys, json
d = json.load(sys.stdin)
print(f'音频URL: {d.get(\"audioUrl\", \"无\")}')
print(f'音频提取: {\"成功\" if d.get(\"audioExtracted\") else \"失败/未启用\"}')
"

        echo ""
        echo "--- ASR结果 ---"
        echo "$RESULT" | python -c "
import sys, json
d = json.load(sys.stdin)
text = d.get('asrText', '')
print(f'转写长度: {d.get(\"asrTextLength\", 0)}')
if text:
    print(f'转写内容: {text[:200]}...' if len(text) > 200 else f'转写内容: {text}')
"

        echo ""
        echo "--- 分析结果 ---"
        echo "$RESULT" | python -c "
import sys, json
d = json.load(sys.stdin)
result = d.get('analysisResult', '')
if result:
    print(result[:500] + '...' if len(result) > 500 else result)
"

        echo ""
        echo "--- 耗时统计 ---"
        echo "$RESULT" | python -c "
import sys, json
d = json.load(sys.stdin)
sd = d.get('stepDurations', {})
print(f'  下载视频: {sd.get(\"download\", 0)}ms')
print(f'  视频抽帧: {sd.get(\"frameExtract\", 0)}ms')
print(f'  音频提取: {sd.get(\"audioExtract\", 0)}ms')
print(f'  ASR转写: {sd.get(\"asrTranscribe\", 0)}ms')
print(f'  大模型分析: {sd.get(\"imageAnalyze\", 0)}ms')
print(f'  总耗时: {d.get(\"totalDurationMs\", 0)}ms')
"
    else
        MSG=$(echo "$RESULT" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('msg','N/A'))" 2>/dev/null)
        echo "状态: 失败 - $MSG"
    fi
else
    echo "$RESULT"
fi